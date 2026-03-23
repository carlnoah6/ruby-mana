# frozen_string_literal: true

module Mana
  # Routes ~"..." prompts to the LLM engine.
  # Also serves as a backward-compatibility wrapper — older code that
  # instantiates Engine directly is delegated to Engines::LLM.
  class Engine
    class << self
      def run(prompt, caller_binding)
        # Mock mode check (before anything else)
        if Mana.mock_active?
          return Engines::LLM.new(caller_binding).handle_mock(prompt)
        end

        engine = Engines::LLM.new(caller_binding)
        engine.execute(prompt)
      end

      # Delegate to LLM engine
      def handler_stack
        Engines::LLM.handler_stack
      end

      def with_handler(handler = nil, **opts, &block)
        Engines::LLM.with_handler(handler, **opts, &block)
      end

      def all_tools
        Engines::LLM.all_tools
      end
    end

    # Backward compatibility: Engine.new(prompt, binding) delegates to Engines::LLM
    def initialize(prompt, caller_binding)
      @delegate = Engines::LLM.new(caller_binding)
      @prompt = prompt
    end

    def execute
      @delegate.execute(@prompt)
    end

    private

    def method_missing(method, *args, **kwargs, &block)
      if @delegate.respond_to?(method, true)
        @delegate.send(method, *args, **kwargs, &block)
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      @delegate.respond_to?(method, include_private) || super
    end
  end
end
