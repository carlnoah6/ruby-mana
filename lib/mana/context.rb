# frozen_string_literal: true

module Mana
  class Context
    attr_reader :messages, :summaries

    # Initialize with empty conversation context
    def initialize
      @messages = []
      @summaries = []
    end

    # --- Class methods ---

    class << self
      # Return the current thread's context instance (lazy-initialized).
      # Uses config.context_class if set, otherwise Mana::Context.
      def current
        Thread.current[:mana_context] ||= begin
          klass = Mana.config.context_class || self
          klass.new
        end
      end
    end

    # --- Token estimation ---

    # Estimate total token count across short-term messages and summaries.
    def token_count
      count = 0
      @messages.each do |msg|
        content = msg[:content]
        case content
        when String
          # Plain text message
          count += estimate_tokens(content)
        when Array
          # Array of content blocks (tool_use, tool_result, text)
          content.each do |block|
            count += estimate_tokens(block[:text] || block[:content] || "")
          end
        end
      end
      @summaries.each { |s| count += estimate_tokens(s) }
      count
    end

    # Rough token estimate: ~4 characters per token
    def estimate_tokens(text)
      return 0 unless text.is_a?(String)

      (text.length / 4.0).ceil
    end

    # --- Context management ---

    # Clear conversation history and summaries
    def clear!
      clear_messages!
    end

    # Clear conversation history and compaction summaries
    def clear_messages!
      @messages.clear
      @summaries.clear
    end

    # --- Display ---

    # Human-readable summary: counts and token usage
    def inspect
      "#<Mana::Context messages=#{messages_rounds} rounds, tokens=#{token_count}/#{context_window}>"
    end

    private

    # Count conversation rounds (user-prompt messages only, not tool results)
    def messages_rounds
      @messages.count { |m| m[:role] == "user" && m[:content].is_a?(String) }
    end

    def context_window
      Mana.config.context_window
    end
  end
end
