# frozen_string_literal: true

require_relative "mana/version"
require_relative "mana/config"
require_relative "mana/backends/base"
require_relative "mana/backends/anthropic"
require_relative "mana/backends/openai"
require_relative "mana/memory_store"
require_relative "mana/memory"    # kept for backward compatibility until claw migrates
require_relative "mana/context"
require_relative "mana/logger"
require_relative "mana/knowledge"
require_relative "mana/binding_helpers"
require_relative "mana/prompt_builder"
require_relative "mana/tool_handler"
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

    # Reset all global state: config, thread-local context and mock
    def reset!
      @config = Config.new
      Thread.current[:mana_context] = nil
      Thread.current[:mana_memory] = nil  # backward compat for claw transition
      Thread.current[:mana_mock] = nil
      clear_tools!
    end

    # Access current thread's context (public API kept as `memory` for backward compat)
    def memory
      Context.current
    end

    # --- Tool registration ---

    # Register an external tool definition with its handler block.
    # tool_definition is a hash with :name, :description, :input_schema.
    # The handler block receives (input) and returns a result string.
    def register_tool(tool_definition, &handler)
      @registered_tools ||= []
      @tool_handlers ||= {}
      @registered_tools << tool_definition
      @tool_handlers[tool_definition[:name]] = handler
    end

    # Return a copy of the registered tool definitions
    def registered_tools
      @registered_tools ||= []
      @registered_tools.dup
    end

    # Return the name → handler mapping for registered tools
    def tool_handlers
      @tool_handlers ||= {}
    end

    # Clear all registered tools, handlers, and prompt sections
    def clear_tools!
      @registered_tools = []
      @tool_handlers = {}
      @prompt_sections = []
    end

    # --- Prompt section registration ---

    # Register a block that returns text to inject into the system prompt.
    # The block is called each time a prompt is built. Return nil or "" to skip.
    def register_prompt_section(&block)
      @prompt_sections ||= []
      @prompt_sections << block
    end

    # Return the list of registered prompt section blocks
    def prompt_sections
      @prompt_sections ||= []
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
