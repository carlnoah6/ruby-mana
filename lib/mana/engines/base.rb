# frozen_string_literal: true

module Mana
  module Engines
    class Base
      attr_reader :config, :binding

      def initialize(caller_binding, config = Mana.config)
        @binding = caller_binding
        @config = config
      end

      # Execute code/prompt in this engine, return the result.
      # Subclasses must implement this.
      def execute(code)
        raise NotImplementedError, "#{self.class}#execute not implemented"
      end

      # Read a variable from the Ruby binding
      def read_var(name)
        if @binding.local_variables.include?(name.to_sym)
          @binding.local_variable_get(name.to_sym)
        elsif @binding.receiver.respond_to?(name.to_sym, true)
          @binding.receiver.send(name.to_sym)
        else
          raise NameError, "undefined variable: #{name}"
        end
      end

      # Write a variable to the Ruby binding
      def write_var(name, value)
        @binding.local_variable_set(name.to_sym, value)
      end
    end
  end
end
