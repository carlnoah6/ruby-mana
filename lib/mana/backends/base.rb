# frozen_string_literal: true

module Mana
  module Backends
    class Base
      def initialize(config)
        @config = config
      end

      # Send a chat request, return array of content blocks in Anthropic format
      # (normalized). Each backend converts its native response to this format.
      # Returns: [{ type: "text", text: "..." }, { type: "tool_use", id: "...", name: "...", input: {...} }]
      def chat(system:, messages:, tools:, model:, max_tokens: 4096)
        raise NotImplementedError
      end
    end
  end
end
