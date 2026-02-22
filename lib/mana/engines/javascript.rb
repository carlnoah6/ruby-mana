# frozen_string_literal: true

begin
  require "mini_racer"
rescue LoadError
  raise LoadError, "mini_racer gem is required for JavaScript support. Add `gem 'mini_racer'` to your Gemfile."
end

require "json"
require "set"

module Mana
  module Engines
    class JavaScript < Base
      # JS helper code that creates Proxy wrappers for remote Ruby objects.
      # Injected once per V8 context.
      JS_PROXY_HELPER = <<~JS
        (function() {
          if (typeof __mana_create_proxy !== 'undefined') return;

          globalThis.__mana_create_proxy = function(refId, typeName) {
            var proxy = new Proxy({ __mana_ref: refId, __mana_type: typeName }, {
              get: function(target, prop) {
                if (prop === '__mana_ref') return target.__mana_ref;
                if (prop === '__mana_type') return target.__mana_type;
                if (prop === '__mana_alive') return ruby.__ref_alive(refId);
                if (prop === 'release') return function() { ruby.__ref_release(refId); };
                if (prop === 'toString' || prop === Symbol.toPrimitive) {
                  return function() { return ruby.__ref_to_s(refId); };
                }
                if (prop === 'inspect') {
                  return function() { return 'RemoteRef<' + typeName + '#' + refId + '>'; };
                }
                if (typeof prop === 'symbol') return undefined;
                return function() {
                  var args = Array.prototype.slice.call(arguments);
                  return ruby.__ref_call(refId, prop, JSON.stringify(args));
                };
              }
            });
            if (typeof __mana_ref_gc !== 'undefined') {
              __mana_ref_gc.register(proxy, refId);
            }
            return proxy;
          };

          // FinalizationRegistry for automatic GC of remote refs
          if (typeof FinalizationRegistry !== 'undefined') {
            globalThis.__mana_ref_gc = new FinalizationRegistry(function(refId) {
              try { ruby.__ref_release(refId); } catch(e) {}
            });
          }
        })();
      JS

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
        ObjectRegistry.reset!
      end

      def execute(code)
        ctx = self.class.context

        # 1. Attach Ruby callbacks (methods + effects + ref operations)
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

      def attach_ruby_callbacks(ctx)
        attached = Thread.current[:mana_js_callbacks_attached] ||= Set.new

        # Install the JS Proxy helper (once per context)
        unless attached.include?("__proxy_helper")
          ctx.eval(JS_PROXY_HELPER)
          attached << "__proxy_helper"
        end

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

        # Remote reference operations
        attach_ref_callbacks(ctx, attached)

        # Attach methods from the caller's receiver
        attach_receiver_methods(ctx, attached)

        # Attach registered Mana effects
        attach_effects(ctx, attached)
      end

      # Attach callbacks for operating on remote Ruby object references from JS.
      def attach_ref_callbacks(ctx, attached)
        registry = ObjectRegistry.current

        unless attached.include?("ruby.__ref_call")
          ctx.attach("ruby.__ref_call", proc { |ref_id, method_name, args_json|
            obj = registry.get(ref_id)
            raise "Remote reference #{ref_id} has been released" unless obj

            args = args_json ? JSON.parse(args_json) : []
            result = obj.public_send(method_name.to_sym, *args)
            json_safe(result)
          })
          attached << "ruby.__ref_call"
        end

        unless attached.include?("ruby.__ref_release")
          ctx.attach("ruby.__ref_release", proc { |ref_id|
            registry.release(ref_id)
            nil
          })
          attached << "ruby.__ref_release"
        end

        unless attached.include?("ruby.__ref_alive")
          ctx.attach("ruby.__ref_alive", proc { |ref_id|
            registry.registered?(ref_id)
          })
          attached << "ruby.__ref_alive"
        end

        unless attached.include?("ruby.__ref_to_s")
          ctx.attach("ruby.__ref_to_s", proc { |ref_id|
            obj = registry.get(ref_id)
            obj ? obj.to_s : "released"
          })
          attached << "ruby.__ref_to_s"
        end
      end

      def attach_receiver_methods(ctx, attached)
        receiver = @binding.receiver
        user_methods = receiver.class.instance_methods(false) -
                       Object.instance_methods -
                       [:~@]

        user_methods.each do |method_name|
          key = "ruby.#{method_name}"
          next if attached.include?(key)

          recv = receiver
          ctx.attach(key, proc { |*args| json_safe(recv.send(method_name, *args)) })
          attached << key
        end
      end

      def attach_effects(ctx, attached)
        Mana::EffectRegistry.registry.each do |name, effect|
          key = "ruby.#{name}"
          next if attached.include?(key)

          eff = effect
          ctx.attach(key, proc { |*args|
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
          inject_value(ctx, var_name.to_s, value)
        rescue => e
          next
        end
      end

      # Inject a single value into the JS context.
      # Simple types are serialized to JSON. Complex objects become remote ref proxies.
      def inject_value(ctx, name, value)
        case value
        when Numeric, String, TrueClass, FalseClass, NilClass
          ctx.eval("var #{name} = #{JSON.generate(value)}")
        when Symbol
          ctx.eval("var #{name} = #{JSON.generate(value.to_s)}")
        when Array
          ctx.eval("var #{name} = #{JSON.generate(serialize_array(value))}")
        when Hash
          ctx.eval("var #{name} = #{JSON.generate(serialize_hash(value))}")
        else
          # Complex object → register and create JS Proxy
          ref_id = ObjectRegistry.current.register(value)
          ctx.eval("var #{name} = __mana_create_proxy(#{ref_id}, #{JSON.generate(value.class.name)})")
        end
      end

      def serialize_array(arr)
        arr.map { |v| simple_value?(v) ? serialize_simple(v) : v.to_s }
      end

      def serialize_hash(hash)
        hash.transform_keys(&:to_s).transform_values { |v|
          simple_value?(v) ? serialize_simple(v) : v.to_s
        }
      end

      def simple_value?(value)
        case value
        when Numeric, String, Symbol, TrueClass, FalseClass, NilClass, Array, Hash
          true
        else
          false
        end
      end

      def serialize_simple(value)
        case value
        when Symbol then value.to_s
        when Array then serialize_array(value)
        when Hash then serialize_hash(value)
        else value
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
        code.scan(/\b(?:const|let|var)\s+(\w+)\s*=/).each { |m| vars << m[0] }
        code.scan(/^(\w+)\s*=[^=>]/).each { |m| vars << m[0] }
        vars.uniq
      end

      def deserialize(value)
        value
      end

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
