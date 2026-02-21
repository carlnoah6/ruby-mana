# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Mana
  module Backends
    class OpenAI < Base
      def chat(system:, messages:, tools:, model:, max_tokens: 4096)
        uri = URI("#{@config.base_url}/v1/chat/completions")
        body = {
          model: model,
          max_completion_tokens: max_tokens,
          messages: convert_messages(system, messages),
          tools: convert_tools(tools)
        }

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 120

        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req["Authorization"] = "Bearer #{@config.api_key}"
        req.body = JSON.generate(body)

        res = http.request(req)
        raise LLMError, "HTTP #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

        parsed = JSON.parse(res.body, symbolize_names: true)
        normalize_response(parsed)
      end

      private

      # Convert Anthropic-style messages to OpenAI format
      def convert_messages(system, messages)
        result = [{ role: "system", content: system }]

        messages.each do |msg|
          case msg[:role]
          when "user"
            converted = convert_user_message(msg)
            if converted.is_a?(Array)
              result.concat(converted)
            else
              result << converted
            end
          when "assistant"
            result << convert_assistant_message(msg)
          end
        end

        result
      end

      def convert_user_message(msg)
        content = msg[:content]

        # Plain text user message
        return { role: "user", content: content } if content.is_a?(String)

        # Array of content blocks — may contain tool_result blocks
        if content.is_a?(Array) && content.all? { |b| b[:type] == "tool_result" || b["type"] == "tool_result" }
          # Convert each tool_result to an OpenAI tool message
          return content.map do |block|
            {
              role: "tool",
              tool_call_id: block[:tool_use_id] || block["tool_use_id"],
              content: (block[:content] || block["content"]).to_s
            }
          end
        end

        # Other array content (e.g. text blocks) — join as string
        if content.is_a?(Array)
          texts = content.map { |b| b[:text] || b["text"] }.compact
          return { role: "user", content: texts.join("\n") }
        end

        { role: "user", content: content.to_s }
      end

      def convert_assistant_message(msg)
        content = msg[:content]

        # Simple text response
        if content.is_a?(String)
          return { role: "assistant", content: content }
        end

        # Array of content blocks — may contain tool_use
        if content.is_a?(Array)
          text_parts = []
          tool_calls = []

          content.each do |block|
            type = block[:type] || block["type"]
            case type
            when "text"
              text_parts << (block[:text] || block["text"])
            when "tool_use"
              tool_calls << {
                id: block[:id] || block["id"],
                type: "function",
                function: {
                  name: block[:name] || block["name"],
                  arguments: JSON.generate(block[:input] || block["input"] || {})
                }
              }
            end
          end

          msg_hash = { role: "assistant" }
          msg_hash[:content] = text_parts.join("\n") unless text_parts.empty?
          msg_hash[:tool_calls] = tool_calls unless tool_calls.empty?
          return msg_hash
        end

        { role: "assistant", content: content.to_s }
      end

      # Convert Anthropic tool definitions to OpenAI function calling format
      def convert_tools(tools)
        tools.map do |tool|
          {
            type: "function",
            function: {
              name: tool[:name],
              description: tool[:description] || "",
              parameters: tool[:input_schema] || {}
            }
          }
        end
      end

      # Convert OpenAI response back to Anthropic-style content blocks
      def normalize_response(parsed)
        choice = parsed.dig(:choices, 0, :message)
        return [] unless choice

        blocks = []

        # Text content
        if choice[:content] && !choice[:content].empty?
          blocks << { type: "text", text: choice[:content] }
        end

        # Tool calls
        if choice[:tool_calls]
          choice[:tool_calls].each do |tc|
            func = tc[:function]
            blocks << {
              type: "tool_use",
              id: tc[:id],
              name: func[:name],
              input: JSON.parse(func[:arguments], symbolize_names: true)
            }
          end
        end

        blocks
      end
    end
  end
end
