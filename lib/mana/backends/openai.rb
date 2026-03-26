# frozen_string_literal: true

module Mana
  module Backends
    # OpenAI-compatible backend (GPT, Groq, DeepSeek, Ollama, etc.)
    #
    # Translates between Mana's internal format (Anthropic-style) and OpenAI's:
    #   - system prompt: top-level `system` → system message
    #   - tool calls: `tool_use`/`tool_result` blocks → `tool_calls` + `role: "tool"`
    #   - response: `choices` → content blocks
    class OpenAI < Base
      def chat(system:, messages:, tools:, model:, max_tokens: 4096)
        uri = URI("#{@config.effective_base_url}/v1/chat/completions")
        parsed = http_post(uri, {
          model: model,
          max_completion_tokens: max_tokens,
          messages: convert_messages(system, messages),
          tools: convert_tools(tools)
        }, {
          "Authorization" => "Bearer #{@config.api_key}"
        })
        normalize_response(parsed)
      end

      private

      # Convert Anthropic-style messages to OpenAI format.
      def convert_messages(system, messages)
        result = [{ role: "system", content: system }]

        messages.each do |msg|
          case msg[:role]
          when "user"
            converted = convert_user_message(msg)
            converted.is_a?(Array) ? result.concat(converted) : result << converted
          when "assistant"
            result << convert_assistant_message(msg)
          end
        end

        result
      end

      def convert_user_message(msg)
        content = msg[:content]

        return { role: "user", content: content } if content.is_a?(String)

        if content.is_a?(Array) && content.all? { |b| (b[:type] || b["type"]) == "tool_result" }
          return content.map do |block|
            {
              role: "tool",
              tool_call_id: block[:tool_use_id] || block["tool_use_id"],
              content: (block[:content] || block["content"]).to_s
            }
          end
        end

        if content.is_a?(Array)
          texts = content.map { |b| b[:text] || b["text"] }.compact
          return { role: "user", content: texts.join("\n") }
        end

        { role: "user", content: content.to_s }
      end

      def convert_assistant_message(msg)
        content = msg[:content]

        return { role: "assistant", content: content } if content.is_a?(String)

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

      # Convert OpenAI response to Anthropic-style content blocks.
      def normalize_response(parsed)
        choice = parsed.dig(:choices, 0, :message)
        return [] unless choice

        blocks = []

        if choice[:content] && !choice[:content].empty?
          blocks << { type: "text", text: choice[:content] }
        end

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
