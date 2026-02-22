# frozen_string_literal: true

begin
  require "mini_racer"
rescue LoadError
  raise LoadError, "mini_racer gem is required for JavaScript support. Add `gem 'mini_racer'` to your Gemfile."
end

require "json"

module Mana
  module Engines
    class JavaScript < Base
      # Thread-local persistent V8 context (lazy-loaded, long-running)
      def self.context
        Thread.current[:mana_js_context] ||= create_context
      end

      def self.create_context
        MiniRacer::Context.new
      end

      def self.reset!
        ctx = Thread.current[:mana_js_context]
        ctx&.dispose
        Thread.current[:mana_js_context] = nil
        Thread.current[:mana_js_callbacks_attached] = nil
      end

      def execute(code)
        ctx = self.class.context

        # 1. Attach Ruby callbacks (methods + effects) into JS `ruby.*` namespace
        attach_ruby_callbacks(ctx)

        # 2. Inject Ruby variables into JS scope
        inject_ruby_vars(ctx, code)

        # 3. Execute the JS code
        result = ctx.eval(code)

        # 4. Extract any new/modified variables back to Ruby binding
        extract_js_vars(ctx, code)

        result
      end

      private

      # Attach Ruby methods and effects as callable JS functions under `ruby.*`.
      # Uses mini_racer's `attach` to create synchronous callbacks from JS -> Ruby.
      #
      # JS code can then call:
      #   ruby.method_name(arg1, arg2)   -- calls a Ruby method from the caller's scope
      #   ruby.effect_name(arg1)         -- calls a registered Mana effect
      #   ruby.read("var_name")          -- reads a Ruby variable
      #   ruby.write("var_name", value)  -- writes a Ruby variable
      def attach_ruby_callbacks(ctx)
        # Track which callbacks are attached per-context to avoid re-attaching
        attached = Thread.current[:mana_js_callbacks_attached] ||= Set.new

        # ruby.read / ruby.write -- variable bridge
        unless attached.include?("ruby.read")
          bnd = @binding
          ctx.attach("ruby.read", proc { |name|
            sym = name.to_sym
            if bnd.local_variables.include?(sym)
              val = bnd.local_variable_get(sym)
              json_safe(val)
            else
              nil
            end
          })
          attached << "ruby.read"
        end

        unless attached.include?("ruby.write")
          bnd = @binding
          ctx.attach("ruby.write", proc { |name, value|
            bnd.local_variable_set(name.to_sym, value)
            value
          })
          attached << "ruby.write"
        end

        # Attach methods from the caller's receiver (self in the binding)
        attach_receiver_methods(ctx, attached)

        # Attach registered Mana effects
        attach_effects(ctx, attached)
      end

      # Discover methods on the binding's receiver and attach them as ruby.method_name
      def attach_receiver_methods(ctx, attached)
        receiver = @binding.receiver
        # Only attach public methods defined by the user (not Object/Kernel builtins)
        user_methods = receiver.class.instance_methods(false) -
                       Object.instance_methods -
                       [:~@] # exclude the mana operator itself

        user_methods.each do |method_name|
          key = "ruby.#{method_name}"
          next if attached.include?(key)

          recv = receiver
          ctx.attach(key, proc { |*args| json_safe(recv.send(method_name, *args)) })
          attached << key
        end
      end

      # Attach Mana custom effects as ruby.effect_name
      def attach_effects(ctx, attached)
        Mana::EffectRegistry.registry.each do |name, effect|
          key = "ruby.#{name}"
          next if attached.include?(key)

          eff = effect
          ctx.attach(key, proc { |*args|
            # Effects expect keyword args; for JS bridge, accept positional or a single hash
            input = if args.length == 1 && args[0].is_a?(Hash)
                      args[0]
                    elsif eff.params.length == args.length
                      eff.params.zip(args).to_h { |p, v| [p[:name], v] }
                    else
                      {}
                    end
            json_safe(eff.call(input))
          })
          attached << key
        end
      end

      def inject_ruby_vars(ctx, code)
        @binding.local_variables.each do |var_name|
          # Only inject variables actually referenced in the code (word-boundary match)
          pattern = /\b#{Regexp.escape(var_name.to_s)}\b/
          next unless code.match?(pattern)

          value = @binding.local_variable_get(var_name)
          serialized = serialize(value)
          ctx.eval("var #{var_name} = #{JSON.generate(serialized)}")
        rescue => e
          next
        end
      end

      def extract_js_vars(ctx, code)
        declared_vars = extract_declared_vars(code)
        declared_vars.each do |var_name|
          begin
            value = ctx.eval(var_name)
            deserialized = deserialize(value)
            write_var(var_name, deserialized)
          rescue MiniRacer::RuntimeError
            next
          end
        end
      end

      def extract_declared_vars(code)
        vars = []
        # Match: const x = ..., let x = ..., var x = ...
        code.scan(/\b(?:const|let|var)\s+(\w+)\s*=/).each { |m| vars << m[0] }
        # Match: bare assignment at start of line: x = ...
        # But NOT: x === ..., x == ..., x => ...
        code.scan(/^(\w+)\s*=[^=>]/).each { |m| vars << m[0] }
        vars.uniq
      end

      def deserialize(value)
        # JS values come back as Ruby primitives from mini_racer
        # Arrays and Hashes are automatically converted
        value
      end

      # Ensure a value is safe to return through mini_racer (JSON-compatible types)
      def json_safe(value)
        case value
        when Numeric, String, TrueClass, FalseClass, NilClass
          value
        when Symbol
          value.to_s
        when Array
          value.map { |v| json_safe(v) }
        when Hash
          value.transform_keys(&:to_s).transform_values { |v| json_safe(v) }
        else
          value.to_s
        end
      end
    end
  end
end
