# frozen_string_literal: true

require "json"
require "fileutils"

module Mana
  class MemoryStore
    def read(namespace)
      raise NotImplementedError
    end

    def write(namespace, memories)
      raise NotImplementedError
    end

    def clear(namespace)
      raise NotImplementedError
    end
  end

  class FileStore < MemoryStore
    def initialize(base_path = nil)
      @base_path = base_path
    end

    def read(namespace)
      path = file_path(namespace)
      return [] unless File.exist?(path)

      data = JSON.parse(File.read(path), symbolize_names: true)
      data.is_a?(Array) ? data : []
    rescue JSON::ParserError
      []
    end

    def write(namespace, memories)
      path = file_path(namespace)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(memories))
    end

    def clear(namespace)
      path = file_path(namespace)
      File.delete(path) if File.exist?(path)
    end

    private

    def file_path(namespace)
      File.join(base_dir, "#{namespace}.json")
    end

    def base_dir
      return File.join(@base_path, "memory") if @base_path

      custom_path = Mana.config.memory_path
      return File.join(custom_path, "memory") if custom_path

      xdg = ENV["XDG_DATA_HOME"]
      if xdg && !xdg.empty?
        File.join(xdg, "mana", "memory")
      elsif RUBY_PLATFORM.include?("darwin")
        File.join(Dir.home, "Library", "Application Support", "mana", "memory")
      else
        File.join(Dir.home, ".local", "share", "mana", "memory")
      end
    end
  end
end
