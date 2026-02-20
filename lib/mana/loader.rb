# frozen_string_literal: true

require "prism"

module Mana
  # Transforms .nrb files: bare string statements become ~"..." calls.
  #
  # Uses Prism AST to safely identify standalone string literals
  # (strings that appear as statements, not assigned or passed as arguments).
  # In normal Ruby, these are no-ops. In .nrb files, they become LLM prompts.
  module Loader
    class << self
      def transform(source)
        result = Prism.parse(source)
        patches = []

        find_bare_strings(result.value) do |node|
          patches << node.location.start_offset
        end

        return source if patches.empty?

        transformed = source.dup
        patches.sort.reverse_each do |offset|
          transformed.insert(offset, "~")
        end
        transformed
      end

      # Load a .nrb file, transforming bare strings to ~"..." calls.
      # @param path [String] path to the .nrb file
      # @param bind [Binding] binding to evaluate in (default: TOPLEVEL_BINDING)
      def load_nrb(path, bind = TOPLEVEL_BINDING)
        full = File.expand_path(path)
        source = File.read(full)
        transformed = transform(source)
        eval(transformed, bind, full, 1) # rubocop:disable Security/Eval
      end

      # Convenience: load a .nrb file relative to the caller's location.
      # Usage: Mana.load("my_script") or Mana.load("my_script.nrb")
      def load_relative(path)
        caller_dir = File.dirname(caller_locations(1, 1).first.absolute_path || caller_locations(1, 1).first.path)
        full = File.expand_path(path, caller_dir)
        full = "#{full}.nrb" unless full.end_with?(".nrb")
        load_nrb(full)
      end

      private

      def find_bare_strings(node, &block)
        return unless node.respond_to?(:compact_child_nodes)

        case node
        when Prism::StatementsNode
          node.body.each do |child|
            case child
            when Prism::StringNode, Prism::InterpolatedStringNode
              block.call(child)
            else
              find_bare_strings(child, &block)
            end
          end
        else
          node.compact_child_nodes.each { |c| find_bare_strings(c, &block) }
        end
      end
    end
  end

  # Top-level convenience: Mana.load("script") loads script.nrb
  def self.load(path)
    Loader.load_relative(path)
  end
end
