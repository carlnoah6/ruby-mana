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

      def install!
        return if @installed

        @installed = true
        register_hook
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
        when Prism::ClassNode, Prism::ModuleNode, Prism::DefNode,
             Prism::SingletonClassNode, Prism::BlockNode, Prism::LambdaNode,
             Prism::IfNode, Prism::UnlessNode, Prism::WhileNode,
             Prism::UntilNode, Prism::ForNode, Prism::CaseNode,
             Prism::BeginNode, Prism::EnsureNode, Prism::RescueNode
          node.compact_child_nodes.each { |c| find_bare_strings(c, &block) }
        else
          node.compact_child_nodes.each { |c| find_bare_strings(c, &block) }
        end
      end

      def register_hook
        ::Kernel.module_eval do
          alias_method :__mana_original_require_relative, :require_relative

          define_method(:require_relative) do |path|
            caller_dir = File.dirname(caller_locations(1, 1).first.path)
            full = File.expand_path(path, caller_dir)

            # Try .nrb extension
            nrb_path = if full.end_with?(".nrb")
                         full
                       elsif !full.end_with?(".rb") && File.exist?("#{full}.nrb")
                         "#{full}.nrb"
                       end

            if nrb_path && File.exist?(nrb_path)
              source = File.read(nrb_path)
              transformed = Mana::Loader.transform(source)
              eval(transformed, TOPLEVEL_BINDING, nrb_path, 1) # rubocop:disable Security/Eval
            else
              __mana_original_require_relative(path)
            end
          end
        end
      end
    end
  end
end

# Auto-install the loader when mana is required
Mana::Loader.install!
