# frozen_string_literal: true

require_relative "mana/version"
require_relative "mana/config"
require_relative "mana/security_policy"
require_relative "mana/backends/base"
require_relative "mana/backends/anthropic"
require_relative "mana/backends/openai"
require_relative "mana/memory_store"
require_relative "mana/memory"
require_relative "mana/logger"
require_relative "mana/engine"
require_relative "mana/introspect"
require_relative "mana/compiler"
require_relative "mana/string_ext"
require_relative "mana/mixin"

module Mana
  class Error < StandardError; end
  class ConfigError < Error; end
  class MaxIterationsError < Error; end
  class LLMError < Error; end
  class MockError < Error; end

  class << self
    # Return the global config singleton (lazy-initialized)
    def config
      @config ||= Config.new
    end

    # Yield the config for modification, return the config instance
    def configure
      yield(config) if block_given?
      config
    end

    # Shortcut to set the model name directly
    def model=(model)
      config.model = model
    end

    # Reset all global state: config, thread-local memory and mock
    def reset!
      @config = Config.new
      Thread.current[:mana_memory] = nil
      Thread.current[:mana_mock] = nil
    end

    # Access current thread's memory
    def memory
      Memory.current
    end

    # Run a block in incognito mode (no memory)
    def incognito(&block)
      Memory.incognito(&block)
    end

    # View generated source for a mana-compiled method
    def source(method_name, owner: nil)
      Compiler.source(method_name, owner: owner)
    end

    # Cache directory for compiled methods
    def cache_dir=(dir)
      Compiler.cache_dir = dir
    end
  end
end

require_relative "mana/mock"
