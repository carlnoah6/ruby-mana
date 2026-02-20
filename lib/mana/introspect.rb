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

      def walk(node, &block)
        stack = [node]
        while (current = stack.pop)
          next unless current.respond_to?(:compact_child_nodes)

          block.call(current)
          stack.concat(current.compact_child_nodes)
        end
      end

      def extract_params(def_node)
        params_node = def_node.parameters
        return [] unless params_node

        result = []

        # Required parameters
        (params_node.requireds || []).each do |p|
          result << param_name(p)
        end

        # Optional parameters
        (params_node.optionals || []).each do |p|
          result << "#{param_name(p)}=..."
        end

        # Rest parameter
        if params_node.rest && !params_node.rest.is_a?(Prism::ImplicitRestNode)
          name = params_node.rest.name
          result << "*#{name || ''}"
        end

        # Keyword parameters
        (params_node.keywords || []).each do |p|
          case p
          when Prism::RequiredKeywordParameterNode
            result << "#{p.name}:"
          when Prism::OptionalKeywordParameterNode
            result << "#{p.name}: ..."
          end
        end

        # Keyword rest
        if params_node.keyword_rest.is_a?(Prism::KeywordRestParameterNode)
          name = params_node.keyword_rest.name
          result << "**#{name || ''}"
        end

        # Block parameter
        if params_node.block
          result << "&#{params_node.block.name || ''}"
        end

        result
      end

      def param_name(node)
        case node
        when Prism::RequiredParameterNode
          node.name.to_s
        when Prism::OptionalParameterNode
          node.name.to_s
        else
          node.respond_to?(:name) ? node.name.to_s : "_"
        end
      end
    end
  end
end
