# frozen_string_literal: true

module Mana
  module LLM
    # Base interface for LLM clients.
    # Subclass and implement #chat to add new providers.
    class Base
      def initialize(config)
        @config = config
      end

      # Send a chat request with tools.
      # Returns an array of content blocks (tool_use / text).
      def chat(system:, messages:, tools:)
        raise NotImplementedError, "#{self.class}#chat not implemented"
      end
    end
  end
end
