# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Mana
  module Backends
    class Anthropic < Base
      def chat(system:, messages:, tools:, model:, max_tokens: 4096)
        uri = URI("#{@config.base_url}/v1/messages")
        body = {
          model: model,
          max_tokens: max_tokens,
          system: system,
          tools: tools,
          messages: messages
        }

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 120

        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req["x-api-key"] = @config.api_key
        req["anthropic-version"] = "2023-06-01"
        req.body = JSON.generate(body)

        res = http.request(req)
        raise LLMError, "HTTP #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

        parsed = JSON.parse(res.body, symbolize_names: true)
        parsed[:content] || []
      end
    end
  end
end
