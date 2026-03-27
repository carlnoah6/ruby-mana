# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Mana
  module Backends
    # Base class for LLM backends. Provides shared HTTP infrastructure
    # and the factory method for backend resolution.
    class Base
      # Model name pattern for auto-detecting Anthropic backend
      ANTHROPIC_PATTERN = /^claude-/i

      def initialize(config)
        @config = config
      end

      # Send a chat request. Subclasses must implement this.
      def chat(system:, messages:, tools:, model:, max_tokens: 4096)
        raise NotImplementedError, "#{self.class}#chat not implemented"
      end

      # --- Factory method ---

      # Resolve a backend instance from configuration.
      # Priority: pre-built instance > explicit name > auto-detect from model name.
      def self.for(config)
        return config.backend if config.backend.is_a?(Base)

        config.validate!

        case config.backend&.to_s
        when "openai" then OpenAI.new(config)
        when "anthropic" then Anthropic.new(config)
        else
          config.model.match?(ANTHROPIC_PATTERN) ? Anthropic.new(config) : OpenAI.new(config)
        end
      end

      private

      # Shared HTTP POST with error handling and timeout support.
      # Returns parsed JSON response body.
      def http_post(uri, body, headers = {})
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @config.timeout
        http.read_timeout = @config.timeout

        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        headers.each { |k, v| req[k] = v }
        req.body = JSON.generate(body)

        res = http.request(req)
        raise LLMError, "HTTP #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

        JSON.parse(res.body, symbolize_names: true)
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise LLMError, "Request timed out: #{e.message}"
      end

      # Streaming HTTP POST — yields parsed SSE events as hashes.
      # Used by chat_stream for real-time output.
      def http_post_stream(uri, body, headers = {})
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @config.timeout
        http.read_timeout = @config.timeout

        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        headers.each { |k, v| req[k] = v }
        req.body = JSON.generate(body)

        http.request(req) do |res|
          raise LLMError, "HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

          buffer = +""
          res.read_body do |chunk|
            buffer << chunk
            while (idx = buffer.index("\n\n"))
              line = buffer.slice!(0, idx + 2).strip
              next if line.empty?

              # Parse SSE: "event: type\ndata: {...}"
              data_line = line.split("\n").find { |l| l.start_with?("data: ") }
              next unless data_line

              json_str = data_line.sub("data: ", "")
              next if json_str == "[DONE]"

              event = JSON.parse(json_str, symbolize_names: true)
              yield event if block_given?
            end
          end
        end
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise LLMError, "Request timed out: #{e.message}"
      rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
        raise LLMError, "Connection failed: #{e.message}"
      end
    end
  end
end
