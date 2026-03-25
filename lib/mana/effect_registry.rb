# frozen_string_literal: true

module Mana
  # Registry for custom effect handlers.
  #
  # Users define effects that become LLM tools automatically:
  #
  #   Mana.define_effect :query_db,
  #     description: "Execute a SQL query" do |sql:|
  #       DB.execute(sql)
  #     end
  #
  # The block's keyword parameters become the tool's input schema.
  # The block's return value is serialized and sent back to the LLM.
  module EffectRegistry
    class EffectDefinition
      attr_reader :name, :description, :handler, :params

      # Initialize an effect with a name, optional description, and handler block
      def initialize(name, description: nil, &handler)
        @name = name.to_s
        @description = description || @name
        @handler = handler
        @params = extract_params(handler)
      end

      # Convert to LLM tool definition (JSON schema for the LLM to call)
      def to_tool
        properties = {}
        required = []

        # Build JSON schema properties from extracted block parameters
        @params.each do |param|
          properties[param[:name]] = {
            type: infer_type(param[:default]),
            description: param[:name]
          }
          required << param[:name] if param[:required]
        end

        tool = {
          name: @name,
          description: @description,
          input_schema: {
            type: "object",
            properties: properties
          }
        }
        tool[:input_schema][:required] = required unless required.empty?
        tool
      end

      # Call the handler with LLM-provided input.
      # Maps input hash keys to the handler block's keyword parameters.
      def call(input)
        kwargs = {}
        @params.each do |param|
          key = param[:name]
          # LLM provided a value for this parameter
          if input.key?(key)
            kwargs[key.to_sym] = input[key]
          elsif param[:default] != :__mana_no_default__
            # Optional parameter — let the block use its own default
          elsif param[:required]
            raise Mana::Error, "missing required parameter: #{key}"
          end
        end

        # Call the handler: no-arg or with keyword args
        if kwargs.empty? && @params.empty?
          @handler.call
        else
          @handler.call(**kwargs)
        end
      end

      private

      # Extract parameter metadata from the handler block's signature.
      # Used to build the JSON schema for the LLM tool definition.
      def extract_params(block)
        return [] unless block

        block.parameters.map do |(type, name)|
          # Map Ruby parameter types to schema metadata
          case type
          when :keyreq
            # Required keyword parameter (e.g. `sql:`)
            { name: name.to_s, required: true, default: :__mana_no_default__ }
          when :key
            # Optional keyword parameter (e.g. `limit: 10`)
            # Default not recoverable via reflection, marked as optional
            { name: name.to_s, required: false, default: nil }
          when :keyrest
            # **kwargs — can't generate a fixed schema, skip
            nil
          else
            # Positional args — treat as required string params
            { name: name.to_s, required: true, default: :__mana_no_default__ } if name
          end
        end.compact
      end

      # Infer JSON schema type from a Ruby default value.
      # Maps Ruby types to their JSON schema equivalents; defaults to "string".
      def infer_type(default)
        case default
        when Integer then "integer"
        when Float then "number"
        when TrueClass, FalseClass then "boolean"
        when Array then "array"
        when Hash then "object"
        else "string"
        end
      end
    end

    RESERVED_EFFECTS = %w[read_var write_var read_attr write_attr call_func done remember].freeze

    class << self
      # Lazy-initialized hash of name -> EffectDefinition
      def registry
        @registry ||= {}
      end

      # Register a custom effect. Rejects names that conflict with built-in tools.
      def define(name, description: nil, &handler)
        name_s = name.to_s
        if RESERVED_EFFECTS.include?(name_s)
          raise Mana::Error, "cannot override built-in effect: #{name_s}"
        end

        registry[name_s] = EffectDefinition.new(name, description: description, &handler)
      end

      # Remove a custom effect by name
      def undefine(name)
        registry.delete(name.to_s)
      end

      # Check if a custom effect is registered
      def defined?(name)
        registry.key?(name.to_s)
      end

      # Look up a custom effect by name
      def get(name)
        registry[name.to_s]
      end

      # Generate tool definitions for all registered effects
      def tool_definitions
        registry.values.map(&:to_tool)
      end

      # Remove all registered custom effects
      def clear!
        @registry = {}
      end

      # Handle a tool call if it matches a registered effect
      # Returns [handled, result] — handled is true if we processed it
      def handle(name, input)
        effect = get(name)
        return [false, nil] unless effect

        result = effect.call(input)
        [true, result]
      end
    end
  end
end
