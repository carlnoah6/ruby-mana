# frozen_string_literal: true

require "prism"

module Mana
  # Introspects the caller's source file to discover user-defined methods.
  # Uses Prism AST to extract `def` nodes with their parameter signatures,
  # descriptions (from comments above the def), and parameter types (from YARD @param tags).
  module Introspect
    class << self
      # Extract method definitions from a Ruby source file.
      # Returns an array of { name:, params:, description:, param_types: } hashes.
      def methods_from_file(path)
        return [] unless path && File.exist?(path)

        source = File.read(path)
        source_lines = source.lines
        result = Prism.parse(source)
        methods = []

        walk(result.value) do |node|
          next unless node.is_a?(Prism::DefNode)

          params = extract_params(node)
          description, param_types = extract_comments(node, source_lines)
          methods << {
            name: node.name.to_s,
            params: params,
            description: description,
            param_types: param_types
          }
        end

        methods
      end

      # Format discovered methods as a string for the system prompt.
      # Includes descriptions when available.
      def format_for_prompt(methods)
        return "" if methods.empty?

        lines = methods.map do |m|
          sig = m[:params].empty? ? m[:name] : "#{m[:name]}(#{m[:params].join(', ')})"
          if m[:description]
            "  #{sig} — #{m[:description]}"
          else
            "  #{sig}"
          end
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

      # Extract description and @param types from comments above a def node.
      # Supports YARD-style comments:
      #   # Description text here
      #   # @param name [Type] description
      def extract_comments(def_node, source_lines)
        def_line = def_node.location.start_line - 1  # 0-indexed
        description_parts = []
        param_types = {}

        # Walk backwards from the line above def, collecting # comments
        line_idx = def_line - 1
        comment_lines = []
        while line_idx >= 0
          line = source_lines[line_idx]&.strip
          break unless line&.start_with?("#")
          comment_lines.unshift(line)
          line_idx -= 1
        end

        comment_lines.each do |line|
          text = line.sub(/^#\s?/, "")
          if text.match?(/^@param\s/)
            # @param name [Type] description
            match = text.match(/^@param\s+(\w+)\s+\[(\w+)\]/)
            if match
              param_types[match[1]] = match[2].downcase
            end
          elsif text.match?(/^@return\s/)
            # Skip @return tags
          else
            description_parts << text unless text.empty?
          end
        end

        description = description_parts.empty? ? nil : description_parts.join(" ")
        [description, param_types]
      end

      # Extract all parameter signatures from a DefNode's parameter list.
      def extract_params(def_node)
        params_node = def_node.parameters
        return [] unless params_node

        result = []

        (params_node.requireds || []).each do |p|
          result << param_name(p)
        end

        (params_node.optionals || []).each do |p|
          result << "#{param_name(p)}=..."
        end

        if params_node.rest && !params_node.rest.is_a?(Prism::ImplicitRestNode)
          name = params_node.rest.name
          result << "*#{name || ''}"
        end

        (params_node.keywords || []).each do |p|
          case p
          when Prism::RequiredKeywordParameterNode
            result << "#{p.name}:"
          when Prism::OptionalKeywordParameterNode
            result << "#{p.name}: ..."
          end
        end

        if params_node.keyword_rest.is_a?(Prism::KeywordRestParameterNode)
          name = params_node.keyword_rest.name
          result << "**#{name || ''}"
        end

        if params_node.block
          result << "&#{params_node.block.name || ''}"
        end

        result
      end

      def param_name(node)
        case node
        when Prism::RequiredParameterNode, Prism::OptionalParameterNode
          node.name.to_s
        else
          node.respond_to?(:name) ? node.name.to_s : "_"
        end
      end
    end
  end
end
