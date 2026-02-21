# frozen_string_literal: true

module Mana
  module Namespace
    class << self
      def detect
        configured || from_git_repo || from_gemfile_dir || from_pwd || "default"
      end

      def configured
        ns = Mana.config.namespace
        ns unless ns.nil? || ns.to_s.empty?
      end

      def from_git_repo
        dir = `git rev-parse --show-toplevel 2>/dev/null`.strip
        return nil if dir.empty?

        File.basename(dir)
      end

      def from_gemfile_dir
        dir = Dir.pwd
        loop do
          return File.basename(dir) if File.exist?(File.join(dir, "Gemfile"))

          parent = File.dirname(dir)
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
