# frozen_string_literal: true

begin
  require "pycall"
rescue LoadError
  raise LoadError, "pycall gem is required for Python support. Add `gem 'pycall'` to your Gemfile."
end

require "json"

module Mana
  module Engines
    class Python < Base
      # Python helper code injected once per namespace.
      # Sets up weak-ref tracking so when Python drops a reference to a
      # complex Ruby object, the ObjectRegistry is notified.
      PY_GC_HELPER = <<~PYTHON
        import weakref as _mana_wr
        import builtins as _mana_bi
        _mana_bi._mana_weakref = _mana_wr

        class __ManaRef:
            """Weak-ref release notifier for Ruby objects passed to Python."""
            _release_fn = None
            _instances = {}

            @classmethod
            def set_release_fn(cls, fn):
                cls._release_fn = fn

            @classmethod
            def track(cls, ref_id, obj):
                """Track a Ruby object. When Python GC collects it, notify Ruby."""
                import builtins
                _wr = builtins._mana_weakref
                try:
                    ref = _wr.ref(obj, lambda r, rid=ref_id: cls._release(rid))
                    cls._instances[ref_id] = ref
                except TypeError:
                    # Some objects can't be weakly referenced; skip them
                    pass

            @classmethod
            def _release(cls, ref_id):
                cls._instances.pop(ref_id, None)
                if cls._release_fn:
                    try:
                        cls._release_fn(ref_id)
                    except Exception:
                        pass

            @classmethod
            def release_all(cls):
                for ref_id in list(cls._instances.keys()):
                    cls._release(ref_id)
      PYTHON

      # Thread-local persistent Python state
      # PyCall shares a single Python interpreter per process,
      # but we track our own variable namespace
      def self.namespace
        Thread.current[:mana_py_namespace] ||= create_namespace
      end

      def self.create_namespace
        PyCall.eval("dict()")
      end

      def self.reset!
        ns = Thread.current[:mana_py_namespace]
        if ns
          begin
            mana_ref = ns["__ManaRef"]
            mana_ref.release_all if mana_ref
          rescue => e
            # ignore
          end
          PyCall.exec("pass") # ensure interpreter is alive
          Thread.current[:mana_py_namespace] = nil
        end
        Thread.current[:mana_py_gc_injected] = nil
        ObjectRegistry.reset!
      end

      def execute(code)
        ns = self.class.namespace

        # 0. Inject GC helper (once per namespace)
        inject_gc_helper(ns)

        # 1. Inject Ruby variables into Python namespace
        inject_ruby_vars(ns, code)

        # 2. Inject the Ruby bridge for Python->Ruby callbacks
        inject_ruby_bridge(ns)

        # 3. Execute Python code in the namespace
        PyCall.exec(code, locals: ns)

        # 4. Extract declared variables back to Ruby
        extract_py_vars(ns, code)

        # Return the last expression value if possible
        begin
          ns["result"]
        rescue
          nil
        end
      rescue PyCall::PyError => e
        raise Mana::Error, "Python execution error: #{e.message}"
      rescue ArgumentError => e
        raise Mana::Error, "Python execution error: #{e.message}"
      end

      private

      def inject_gc_helper(ns)
        return if Thread.current[:mana_py_gc_injected]

        PyCall.exec(PY_GC_HELPER, locals: ns)

        # Wire up the release callback: when Python GC collects a tracked object,
        # __ManaRef calls this proc to release it from the Ruby ObjectRegistry.
        registry = ObjectRegistry.current
        release_fn = proc { |ref_id| registry.release(ref_id.to_i) }
        mana_ref = ns["__ManaRef"]
        mana_ref.set_release_fn(release_fn)

        Thread.current[:mana_py_gc_injected] = true
      end

      def inject_ruby_vars(ns, code)
        @binding.local_variables.each do |var_name|
          value = @binding.local_variable_get(var_name)
          serialized = serialize_for_py(value)
          begin
            ns[var_name.to_s] = serialized
          rescue => e
            next
          end
        end
      end

      # Inject a `ruby` bridge into the Python namespace.
      #
      # The bridge is a Ruby object with method_missing that proxies calls
      # back to the Ruby binding. PyCall automatically wraps it so Python
      # can call methods directly:
      #
      #   ruby.method_name(arg1, arg2)  -- call a Ruby method on the receiver
      #   ruby.read("var")              -- read a Ruby local variable
      #   ruby.write("var", value)      -- write a Ruby local variable
      #   ruby.call_proc("name", args)  -- call a local proc/lambda by name
      #
      # Ruby objects (including the binding receiver) can also be injected
      # directly and called from Python -- PyCall handles the wrapping.
      def inject_ruby_bridge(ns)
        ns["ruby"] = RubyBridge.new(@binding)
      end

      def extract_py_vars(ns, code)
        declared_vars = extract_declared_vars(code)
        declared_vars.each do |var_name|
          next if var_name == "ruby" # skip the bridge object
          begin
            value = ns[var_name]
            deserialized = deserialize_py(value)
            write_var(var_name, deserialized)
          rescue => e
            next
          end
        end
      end

      def extract_declared_vars(code)
        vars = []
        # Match Python assignments: x = ..., but not x == ... or x += ...
        code.scan(/^(\w+)\s*=[^=]/).each { |m| vars << m[0] }
        # Also match augmented assignments: x += ..., x -= ...
        code.scan(/^(\w+)\s*[+\-*\/]?=/).each { |m| vars << m[0] }
        vars.uniq
      end

      # Serialize Ruby values for Python injection.
      # Simple types are copied. Complex objects are passed directly via PyCall
      # (which wraps them so Python can call their methods) AND registered in
      # the ObjectRegistry for lifecycle tracking + GC notification.
      def serialize_for_py(value)
        case value
        when Numeric, String, TrueClass, FalseClass, NilClass
          value
        when Symbol
          value.to_s
        when Array
          value.map { |v| serialize_for_py(v) }
        when Hash
          value.transform_keys(&:to_s).transform_values { |v| serialize_for_py(v) }
        when Proc, Method
          ref_id = ObjectRegistry.current.register(value)
          track_in_python(ref_id, value)
          value
        else
          ref_id = ObjectRegistry.current.register(value)
          track_in_python(ref_id, value)
          value
        end
      end

      # Tell the Python __ManaRef tracker to watch this object via weakref.
      def track_in_python(ref_id, value)
        ns = self.class.namespace
        begin
          mana_ref = ns["__ManaRef"]
          mana_ref.track(ref_id, value) if mana_ref
        rescue => e
          # Non-fatal: some objects can't be weakly referenced in Python
        end
      end

      def deserialize_py(value)
        if defined?(PyCall::PyObjectWrapper) && value.is_a?(PyCall::PyObjectWrapper)
          begin
            value.to_a rescue value.to_s
          rescue
            value.to_s
          end
        else
          value
        end
      end
    end

    # Bridge object injected as `ruby` in the Python namespace.
    # Enables Python->Ruby callbacks via method_missing.
    #
    # Python usage:
    #   ruby.some_method(arg1, arg2)  -- calls method on binding receiver
    #   ruby.read("var_name")         -- reads a Ruby local variable
    #   ruby.write("var_name", val)   -- writes a Ruby local variable
    #   ruby.call_proc("name", args)  -- calls a local proc/lambda by name
    class RubyBridge
      def initialize(caller_binding)
        @binding = caller_binding
        @receiver = caller_binding.receiver
      end

      # Read a Ruby local variable
      def read(name)
        name = name.to_s.to_sym
        if @binding.local_variables.include?(name)
          @binding.local_variable_get(name)
        else
          raise NameError, "undefined Ruby variable '#{name}'"
        end
      end

      # Write a Ruby local variable
      def write(name, value)
        @binding.local_variable_set(name.to_s.to_sym, value)
      end

      # Explicitly call a local proc/lambda by name
      def call_proc(name, *args)
        name = name.to_s.to_sym
        if @binding.local_variables.include?(name)
          val = @binding.local_variable_get(name)
          if val.respond_to?(:call)
            return val.call(*args)
          end
        end
        raise NoMethodError, "no callable '#{name}' in Ruby scope"
      end

      # Proxy unknown method calls to the binding receiver.
      # This lets Python do: ruby.some_method(args)
      def method_missing(name, *args)
        name_s = name.to_s

        # First check local procs/lambdas
        name_sym = name_s.to_sym
        if @binding.local_variables.include?(name_sym)
          val = @binding.local_variable_get(name_sym)
          return val.call(*args) if val.respond_to?(:call)
        end

        # Then try the receiver
        if @receiver.respond_to?(name_s)
          return @receiver.public_send(name_s, *args)
        end

        super
      end

      def respond_to_missing?(name, include_private = false)
        name_s = name.to_s
        name_sym = name_s.to_sym

        # Check local callables
        if @binding.local_variables.include?(name_sym)
          val = @binding.local_variable_get(name_sym)
          return true if val.respond_to?(:call)
        end

        # Check receiver (public methods only)
        return true if @receiver.respond_to?(name_s)

        super
      end
    end
  end
end
