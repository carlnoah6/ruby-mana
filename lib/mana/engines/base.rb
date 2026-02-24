# frozen_string_literal: true

module Mana
  module Engines
    class Base
      attr_reader :config, :binding

      def initialize(caller_binding, config = Mana.config)
        @binding = caller_binding
        @config = config
      end

      # --- Capability queries ---
      # Subclasses override to declare what they support.

      # Is this an execution engine (Ruby/JS/Python) or a reasoning engine (LLM)?
      # Execution engines can execute code, hold state, and be called bidirectionally.
      # Reasoning engines process natural language but cannot hold references or state.
      def execution_engine?
        true
      end

      # Can this engine hold remote references to objects in other engines?
      # Derived from execution_engine? — only execution engines support remote refs.
      def supports_remote_ref?
        execution_engine?
      end

      # Can code in this engine call back into another engine (bidirectional)?
      # Derived from execution_engine? — only execution engines support bidirectional calls.
      def supports_bidirectional?
        execution_engine?
      end

      # Does this engine maintain mutable state across calls?
      # Derived from execution_engine? — only execution engines maintain state.
      def supports_state?
        execution_engine?
      end

      # Execute code/prompt in this engine, return the result
      # Subclasses must implement this
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

      # Serialize a Ruby value for cross-language transfer
      # Simple types: copy. Complex objects: will be remote refs (future)
      def serialize(value)
        case value
        when Numeric, String, Symbol, TrueClass, FalseClass, NilClass
          value
        when Array
          value.map { |v| serialize(v) }
        when Hash
          value.transform_values { |v| serialize(v) }
        else
          value.to_s
        end
      end
    end
  end
end
