# frozen_string_literal: true

module Mana
  module Backends
    # Native Anthropic Claude backend.
    #
    # Sends requests directly to the Anthropic Messages API (/v1/messages).
    # No format conversion needed — Mana's internal format matches Anthropic's.
    class Anthropic < Base
      def chat(system:, messages:, tools:, model:, max_tokens: 4096)
        uri = URI("#{@config.effective_base_url}/v1/messages")
        parsed = http_post(uri, { model:, max_tokens:, system:, tools:, messages: }, {
          "x-api-key" => @config.api_key,
          "anthropic-version" => "2023-06-01"
        })
        parsed[:content] || []
      end
    end
  end
end
