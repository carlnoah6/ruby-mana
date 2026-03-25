# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Mana
  module Backends
    # OpenAI-compatible backend (GPT, Groq, DeepSeek, Ollama, etc.)
    #
    # Internally, Mana uses Anthropic's message format as the canonical
    # representation. This backend translates between the two formats:
    #   Anthropic → OpenAI  (outgoing request)
    #   OpenAI → Anthropic  (incoming response)
    #
    # Key differences handled:
    #   - system prompt: Anthropic uses top-level `system`, OpenAI uses a system message
    #   - tool calls: Anthropic uses `tool_use`/`tool_result` content blocks,
    #     OpenAI uses `tool_calls` array and `role: "tool"` messages
    #   - response: Anthropic returns `content` blocks, OpenAI returns `choices`
    class OpenAI
      def initialize(config)
        @config = config
      end

      # Send a chat completion request and return content blocks in Mana's
      # internal format (Anthropic-style content blocks).
      def chat(system:, messages:, tools:, model:, max_tokens: 4096)
        uri = URI("#{@config.effective_base_url}/v1/chat/completions")
        body = {
          model: model,
          max_completion_tokens: max_tokens,
          messages: convert_messages(system, messages),
          tools: convert_tools(tools)
        }

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @config.timeout
        http.read_timeout = @config.timeout

        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req["Authorization"] = "Bearer #{@config.api_key}"
        req.body = JSON.generate(body)

        res = http.request(req)
        raise LLMError, "HTTP #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

        parsed = JSON.parse(res.body, symbolize_names: true)
        normalize_response(parsed)
      # Re-raise timeout errors with a clearer message
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise LLMError, "Request timed out: #{e.message}"
      end

      private

      # Convert Anthropic-style messages to OpenAI format.
      # System prompt becomes a system message; user/assistant messages are converted individually.
      def convert_messages(system, messages)
        result = [{ role: "system", content: system }]

        messages.each do |msg|
          # Dispatch by message role
          case msg[:role]
          # User messages may contain plain text or tool_result arrays
          when "user"
            converted = convert_user_message(msg)
            # tool_result conversions return an array of role:"tool" messages
            if converted.is_a?(Array)
              result.concat(converted)
            else
              result << converted
            end
          # Assistant messages may contain text and/or tool_use blocks
          when "assistant"
            result << convert_assistant_message(msg)
          end
        end

        result
      end

      # Convert a single Anthropic user message to OpenAI format.
      # Handles three content shapes: plain string, tool_result array, or text block array.
      def convert_user_message(msg)
        content = msg[:content]

        # Plain text user message — pass through directly
        return { role: "user", content: content } if content.is_a?(String)

        # Array of tool_result blocks — convert to OpenAI's role:"tool" messages
        if content.is_a?(Array) && content.all? { |b| b[:type] == "tool_result" || b["type"] == "tool_result" }
          return content.map do |block|
            {
              role: "tool",
              tool_call_id: block[:tool_use_id] || block["tool_use_id"],
              content: (block[:content] || block["content"]).to_s
            }
          end
        end

        # Other array content (e.g. text blocks) — join as a single string
        if content.is_a?(Array)
          texts = content.map { |b| b[:text] || b["text"] }.compact
          return { role: "user", content: texts.join("\n") }
        end

        # Fallback: coerce to string
        { role: "user", content: content.to_s }
      end

      # Convert a single Anthropic assistant message to OpenAI format.
      # Separates text blocks and tool_use blocks into OpenAI's content + tool_calls fields.
      def convert_assistant_message(msg)
        content = msg[:content]

        # Simple text response — pass through directly
        if content.is_a?(String)
          return { role: "assistant", content: content }
        end

        # Array of content blocks — split into text parts and tool calls
        if content.is_a?(Array)
          text_parts = []
          tool_calls = []

          content.each do |block|
            type = block[:type] || block["type"]
            # Separate text and tool_use content blocks
            case type
            # Collect text content
            when "text"
              text_parts << (block[:text] || block["text"])
            # Convert tool_use to OpenAI function call format
            when "tool_use"
              # Convert Anthropic tool_use to OpenAI function call format
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

        # Fallback: coerce to string
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

      # Convert OpenAI response back to Anthropic-style content blocks.
      # This is the reverse of convert_messages — normalizes into Mana's canonical format.
      def normalize_response(parsed)
        choice = parsed.dig(:choices, 0, :message)
        return [] unless choice

        blocks = []

        # Extract text content (if any)
        if choice[:content] && !choice[:content].empty?
          blocks << { type: "text", text: choice[:content] }
        end

        # Convert OpenAI function calls back to Anthropic-style tool_use blocks
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
