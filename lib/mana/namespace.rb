# frozen_string_literal: true

module Mana
  # Detects a namespace for isolating long-term memory storage.
  # Fallback order: explicit config > git repo name > Gemfile dir > pwd > "default"
  module Namespace
    class << self
      # Detect the namespace using a fallback chain:
      # explicit config > git repo name > Gemfile directory > pwd > "default"
      def detect
        configured || from_git_repo || from_gemfile_dir || from_pwd || "default"
      end

      # Return the user-configured namespace (if any)
      def configured
        ns = Mana.config.namespace
        ns unless ns.nil? || ns.to_s.empty?
      end

      # Derive namespace from the git repository root directory name
      def from_git_repo
        dir = `git rev-parse --show-toplevel 2>/dev/null`.strip
        return nil if dir.empty?

        File.basename(dir)
      end

      # Walk up the directory tree to find a Gemfile, use that directory's name
      def from_gemfile_dir
        dir = Dir.pwd
        loop do
          return File.basename(dir) if File.exist?(File.join(dir, "Gemfile"))

          parent = File.dirname(dir)
          # Reached filesystem root without finding a Gemfile
          return nil if parent == dir

          dir = parent
        end
      end

      def from_pwd
        File.basename(Dir.pwd)
      end
    end
  end
end
