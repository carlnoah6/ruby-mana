# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Mana
  module LLM
    class Anthropic < Base
      API_URL = "https://api.anthropic.com/v1/messages"
      API_VERSION = "2023-06-01"

      def initialize(config = Mana.config)
        super(config)
        @api_key = config.api_key
        @model = config.model
      end

      def chat(system:, messages:, tools:)
        raise Mana::Error, "Anthropic API key not set" unless @api_key

        body = {
          model: @model,
          max_tokens: 4096,
          temperature: @config.temperature,
          system: system,
          messages: messages,
          tools: tools
        }

        response = post(body)

        unless response.is_a?(Net::HTTPSuccess)
          parsed = JSON.parse(response.body) rescue nil
          error_msg = parsed&.dig("error", "message") || response.body
          raise Mana::Error, "Anthropic API error (#{response.code}): #{error_msg}"
        end

        parsed = JSON.parse(response.body)
        parsed["content"].map { |block| symbolize_keys(block) }
      end

      private

      def post(body)
        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 30
        http.read_timeout = 120
        http.write_timeout = 30

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
