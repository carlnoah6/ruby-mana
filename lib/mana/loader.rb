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
      def load_nrb(path, bind = TOPLEVEL_BINDING)
        source = File.read(path)
        transformed = transform(source)
        eval(transformed, bind, path, 1) # rubocop:disable Security/Eval
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
        else
          node.compact_child_nodes.each { |c| find_bare_strings(c, &block) }
        end
      end

      def register_hook
        # Register .nrb as a loadable extension via Kernel#require_relative override.
        # We use Module.prepend so `super` correctly delegates to the original
        # require_relative (preserving caller-relative path resolution).
        loader_mod = Module.new do
          def require_relative(path)
            # Resolve the path relative to the actual caller's file
            caller_dir = File.dirname(caller_locations(1, 1).first.absolute_path || caller_locations(1, 1).first.path)
            full = File.expand_path(path, caller_dir)

            # Check for .nrb variant
            nrb_path = if full.end_with?(".nrb")
                         full
                       elsif !full.end_with?(".rb") && File.exist?("#{full}.nrb") && !File.exist?("#{full}.rb")
                         "#{full}.nrb"
                       end

            if nrb_path && File.exist?(nrb_path)
              Mana::Loader.load_nrb(nrb_path)
            else
              super(path)
            end
          end
        end

        # Prepend to Object so instance-level require_relative calls are intercepted,
        # but super correctly falls through to the original Kernel#require_relative.
        ::Object.prepend(loader_mod)
      end
    end
  end
end

# Auto-install the loader when mana is required
Mana::Loader.install!
