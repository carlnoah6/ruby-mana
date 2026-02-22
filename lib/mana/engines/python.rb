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
      # Thread-local persistent Python state
      # PyCall shares a single Python interpreter per process,
      # but we track our own variable namespace
      def self.namespace
        Thread.current[:mana_py_namespace] ||= create_namespace
      end

      def self.create_namespace
        # Create a dedicated dict for Mana variables in Python
        PyCall.eval("dict()")
      end

      def self.reset!
        ns = Thread.current[:mana_py_namespace]
        if ns
          PyCall.exec("pass") # ensure interpreter is alive
          Thread.current[:mana_py_namespace] = nil
        end
      end

      def execute(code)
        ns = self.class.namespace

        # 1. Inject Ruby variables into Python namespace
        inject_ruby_vars(ns, code)

        # 2. Execute Python code in the namespace
        PyCall.exec(code, ns)

        # 3. Extract declared variables back to Ruby
        extract_py_vars(ns, code)

        # Return the last expression value if possible
        # Python exec doesn't return values, so we check for a 'result' variable
        begin
          ns["result"]
        rescue
          nil
        end
      end

      private

      def inject_ruby_vars(ns, code)
        @binding.local_variables.each do |var_name|
          value = @binding.local_variable_get(var_name)
          serialized = serialize(value)
          begin
            ns[var_name.to_s] = serialized
          rescue => e
            next
          end
        end
      end

      def extract_py_vars(ns, code)
        declared_vars = extract_declared_vars(code)
        declared_vars.each do |var_name|
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

      def deserialize_py(value)
        # PyCall automatically converts basic Python types to Ruby
        # list -> Array, dict -> Hash, int/float -> Numeric, str -> String
        # For numpy arrays, convert to Ruby array
        if defined?(PyCall) && value.is_a?(PyCall::PyObject)
          begin
            # Try to convert to Ruby native type
            value.to_a rescue value.to_s
          rescue
            value.to_s
          end
        else
          value
        end
      end
    end
  end
end
