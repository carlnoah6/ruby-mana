# frozen_string_literal: true

module Mana
  # Binding manipulation utilities: read/write variables, validate names, serialize values.
  # Mixed into Engine as private methods.
  module BindingHelpers
    VALID_IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_]*\z/

    private

    # Ensure a name is a valid Ruby identifier (prevents injection)
    def validate_name!(name)
      raise Mana::Error, "invalid identifier: #{name.inspect}" unless name.match?(VALID_IDENTIFIER)
    end

    # Resolve a name to a value: try local variable first, then receiver method
    def resolve(name)
      validate_name!(name)
      if @binding.local_variable_defined?(name.to_sym)
        # Found as a local variable in the caller's binding
        @binding.local_variable_get(name.to_sym)
      elsif @binding.receiver.respond_to?(name.to_sym)
        # Found as a public method on the caller's self
        @binding.receiver.public_send(name.to_sym)
      else
        raise NameError, "undefined variable or method '#{name}'"
      end
    end

    # Write a value into the caller's binding, with Ruby 4.0+ singleton method fallback.
    # Only defines a singleton method when the variable doesn't already exist as a local
    # AND the receiver doesn't already have a real method with that name.
    def write_local(name, value)
      validate_name!(name)
      sym = name.to_sym

      # Check if the variable already exists before setting
      existed = @binding.local_variable_defined?(sym)
      @binding.local_variable_set(sym, value)

      # Ruby 4.0+: local_variable_set can no longer create new locals visible
      # in the caller's scope. Define a singleton method ONLY for new variables
      # that don't conflict with existing methods on the receiver.
      unless existed
        receiver = @binding.eval("self")
        # Don't overwrite real instance methods — only add if no method exists
        unless receiver.class.method_defined?(sym) || receiver.class.private_method_defined?(sym)
          old_verbose, $VERBOSE = $VERBOSE, nil
          receiver.define_singleton_method(sym) { value }
          $VERBOSE = old_verbose
          # Track Mana-created singleton method variables so local_variables can include them
          mana_vars = receiver.instance_variable_defined?(:@__mana_vars__) ? receiver.instance_variable_get(:@__mana_vars__) : Set.new
          mana_vars << sym
          receiver.instance_variable_set(:@__mana_vars__, mana_vars)
        end
      end
    end

    # Find the user's source file by walking up the call stack.
    # Used for introspecting available methods in the caller's code.
    def caller_source_path
      # Try binding's source_location first (most direct)
      loc = @binding.source_location
      return loc[0] if loc.is_a?(Array)

      # Fallback: scan caller_locations, skip frames inside the mana gem itself
      caller_locations(4, 20)&.each do |frame|
        path = frame.absolute_path || frame.path
        next if path.nil? || path.include?("mana/")
        return path
      end
      nil
    end

    # Serialize a Ruby value to a string representation the LLM can understand.
    # Handles primitives, collections, and arbitrary objects (via ivar inspection).
    def serialize_value(val)
      case val
      when Time
        # Format Time as a human-readable timestamp string
        val.strftime("%Y-%m-%d %H:%M:%S %z").inspect
      when String, Integer, Float, TrueClass, FalseClass, NilClass
        # Primitives: use Ruby's built-in inspect
        val.inspect
      when Symbol
        # Convert symbol to string for LLM readability
        val.to_s.inspect
      when Array
        # Recursively serialize each element
        "[#{val.map { |v| serialize_value(v) }.join(', ')}]"
      when Hash
        # Recursively serialize key-value pairs
        pairs = val.map { |k, v| "#{serialize_value(k)} => #{serialize_value(v)}" }
        "{#{pairs.join(', ')}}"
      else
        # Arbitrary object: show class name and instance variables
        ivars = val.instance_variables
        obj_repr = ivars.map do |ivar|
          attr_name = ivar.to_s.delete_prefix("@")
          "#{attr_name}: #{val.instance_variable_get(ivar).inspect}" rescue nil
        end.compact.join(", ")
        "#<#{val.class} #{obj_repr}>"
      end
    end
  end
end
