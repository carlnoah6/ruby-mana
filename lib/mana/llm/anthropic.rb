# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Mana
  module LLM
    class Anthropic < Base
      API_URL = "https://api.anthropic.com/v1/messages"
      API_VERSION = "2023-06-01"

      def initialize(api_key: nil, model: nil)
        super()
        @api_key = api_key || Mana.config.api_key
        @model = model || Mana.config.model
      end

      def chat(system:, messages:, tools:)
        raise Mana::Error, "Anthropic API key not set" unless @api_key

        body = {
          model: @model,
          max_tokens: 4096,
          temperature: Mana.config.temperature,
          system: system,
          messages: messages,
          tools: tools
        }

        response = post(body)
        parsed = JSON.parse(response.body)

        if response.code.to_i != 200
          error_msg = parsed.dig("error", "message") || response.body
          raise Mana::Error, "Anthropic API error (#{response.code}): #{error_msg}"
        end

        # Return content blocks with symbolized keys
        parsed["content"].map { |block| symbolize_keys(block) }
      end

      private

      def post(body)
        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["x-api-key"] = @api_key
        request["anthropic-version"] = API_VERSION
        request["content-type"] = "application/json"
        request.body = JSON.generate(body)

        http.request(request)
      end

      def symbolize_keys(hash)
        hash.each_with_object({}) do |(k, v), acc|
          acc[k.to_sym] = v.is_a?(Hash) ? symbolize_keys(v) : v
        end
      end
    end
  end
end
