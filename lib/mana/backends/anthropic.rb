# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Mana
  module Backends
    # Native Anthropic Claude backend.
    #
    # Sends requests directly to the Anthropic Messages API (/v1/messages).
    # No format conversion needed — Mana's internal format matches Anthropic's.
    # Authentication uses x-api-key header (not Bearer token).
    class Anthropic
      def initialize(config)
        @config = config
      end

      # Send a chat request and return content blocks directly from the API.
      def chat(system:, messages:, tools:, model:, max_tokens: 4096)
        uri = URI("#{@config.effective_base_url}/v1/messages")
        body = {
          model: model,
          max_tokens: max_tokens,
          system: system,
          tools: tools,
          messages: messages
        }

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @config.timeout
        http.read_timeout = @config.timeout

        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req["x-api-key"] = @config.api_key
        req["anthropic-version"] = "2023-06-01"
        req.body = JSON.generate(body)

        res = http.request(req)
        raise LLMError, "HTTP #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

        parsed = JSON.parse(res.body, symbolize_names: true)
        parsed[:content] || []
      # Re-raise timeout errors with a clearer message
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise LLMError, "Request timed out: #{e.message}"
      end
    end
  end
end
