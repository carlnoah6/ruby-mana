# frozen_string_literal: true

require "prism"

module Mana
  # Introspects the caller's source file to discover user-defined methods.
  # Uses Prism AST to extract `def` nodes with their parameter signatures.
  module Introspect
    class << self
      # Extract method definitions from a Ruby source file.
      # Returns an array of { name:, params: } hashes.
      #
      # @param path [String] path to the Ruby source file
      # @return [Array<Hash>] method definitions found
      def methods_from_file(path)
        return [] unless path && File.exist?(path)

        source = File.read(path)
        result = Prism.parse(source)
        methods = []

        walk(result.value) do |node|
          next unless node.is_a?(Prism::DefNode)

          params = extract_params(node)
          methods << { name: node.name.to_s, params: params }
        end

        methods
      end

      # Format discovered methods as a string for the system prompt.
      #
      # @param methods [Array<Hash>] from methods_from_file
      # @return [String] formatted method list
      def format_for_prompt(methods)
        return "" if methods.empty?

        lines = methods.map do |m|
          sig = m[:params].empty? ? m[:name] : "#{m[:name]}(#{m[:params].join(', ')})"
          "  #{sig}"
        end

        "Available Ruby functions:\n#{lines.join("\n")}"
      end

      private

      # Breadth-first walk over the AST, yielding each node to the block
      def walk(node, &block)
        queue = [node]
        while (current = queue.shift)
          next unless current.respond_to?(:compact_child_nodes)

          block.call(current)
          queue.concat(current.compact_child_nodes)
        end
      end

      # Extract all parameter signatures from a DefNode's parameter list.
      # Handles required, optional, rest, keyword, keyword rest, and block params.
      def extract_params(def_node)
        params_node = def_node.parameters
        return [] unless params_node

        result = []

        # Required positional parameters
        (params_node.requireds || []).each do |p|
          result << param_name(p)
        end

        # Optional positional parameters (with default values)
        (params_node.optionals || []).each do |p|
          result << "#{param_name(p)}=..."
        end

        # Splat rest parameter (*args)
        if params_node.rest && !params_node.rest.is_a?(Prism::ImplicitRestNode)
          name = params_node.rest.name
          result << "*#{name || ''}"
        end

        # Keyword parameters (required and optional)
        (params_node.keywords || []).each do |p|
          case p
          when Prism::RequiredKeywordParameterNode
            result << "#{p.name}:"
          when Prism::OptionalKeywordParameterNode
            result << "#{p.name}: ..."
          end
        end

        # Double splat keyword rest parameter (**opts)
        if params_node.keyword_rest.is_a?(Prism::KeywordRestParameterNode)
          name = params_node.keyword_rest.name
          result << "**#{name || ''}"
        end

        # Block parameter (&block)
        if params_node.block
          result << "&#{params_node.block.name || ''}"
        end

        result
      end

      # Extract the name string from a parameter AST node
      def param_name(node)
        case node
        when Prism::RequiredParameterNode
          node.name.to_s
        when Prism::OptionalParameterNode
          node.name.to_s
        else
          # Fallback for other node types (e.g. destructured params)
          node.respond_to?(:name) ? node.name.to_s : "_"
        end
      end
    end
  end
end
