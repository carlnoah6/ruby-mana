# frozen_string_literal: true

require_relative "mana/version"
require_relative "mana/config"
require_relative "mana/backends/base"
require_relative "mana/backends/anthropic"
require_relative "mana/backends/openai"
require_relative "mana/backends/registry"
require_relative "mana/effect_registry"
require_relative "mana/namespace"
require_relative "mana/memory_store"
require_relative "mana/context_window"
require_relative "mana/memory"
require_relative "mana/engines/base"
require_relative "mana/engines/llm"
require_relative "mana/engines/ruby_eval"
require_relative "mana/engines/detect"
require_relative "mana/engine"
require_relative "mana/introspect"
require_relative "mana/compiler"
require_relative "mana/string_ext"
require_relative "mana/mixin"

module Mana
  class Error < StandardError; end
  class MaxIterationsError < Error; end
  class LLMError < Error; end
  class MockError < Error; end

  class << self
    def config
      @config ||= Config.new
    end

    def configure
      yield(config) if block_given?
      config
    end

    def model=(model)
      config.model = model
    end

    def handle(handler = nil, **opts, &block)
      Engine.with_handler(handler, **opts, &block)
    end

    def reset!
      @config = Config.new
      EffectRegistry.clear!
      Engines.reset_detector!
      Thread.current[:mana_memory] = nil
      Thread.current[:mana_mock] = nil
      Thread.current[:mana_last_engine] = nil
    end

    # Define a custom effect that becomes an LLM tool
    def define_effect(name, description: nil, &handler)
      EffectRegistry.define(name, description: description, &handler)
    end

    # Remove a custom effect
    def undefine_effect(name)
      EffectRegistry.undefine(name)
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
