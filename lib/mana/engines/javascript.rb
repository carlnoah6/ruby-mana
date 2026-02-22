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
        Thread.current[:mana_js_context]&.dispose
        Thread.current[:mana_js_context] = nil
      end

      def execute(code)
        ctx = self.class.context

        # 1. Scan code for Ruby variable references
        #    Variables from Ruby binding are injected into JS context
        inject_ruby_vars(ctx, code)

        # 2. Execute the JS code
        result = ctx.eval(code)

        # 3. Extract any new/modified variables back to Ruby binding
        extract_js_vars(ctx, code)

        result
      end

      private

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
    end
  end
end
