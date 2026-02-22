# frozen_string_literal: true

module Mana
  class Engine
    class << self
      def run(prompt, caller_binding)
        # Mock mode check (before anything else)
        if Mana.mock_active?
          return Engines::LLM.new(caller_binding).handle_mock(prompt)
        end

        # Detect language engine
        engine_class = detect_engine(prompt)

        # Create engine and execute
        engine = engine_class.new(caller_binding)
        engine.execute(prompt)
      end

      def detect_engine(code)
        # For now: everything goes to LLM
        # Language detection will be added in a later PR
        Engines::LLM
      end

      # Delegate to LLM engine for backward compatibility
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
    # Some tests instantiate Engine directly and call private methods
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
