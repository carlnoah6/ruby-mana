# frozen_string_literal: true

module Mana
  module Backends
    ANTHROPIC_PATTERNS = /^(claude-)/i
    OPENAI_PATTERNS = /^(gpt-|o1-|o3-|chatgpt-|dall-e|tts-|whisper-)/i

    def self.for(config)
      return config.backend if config.backend.is_a?(Base)

      case config.backend&.to_s
      when "openai" then OpenAI.new(config)
      when "anthropic" then Anthropic.new(config)
      else
        # Auto-detect from model name
        case config.model
        when ANTHROPIC_PATTERNS then Anthropic.new(config)
        else OpenAI.new(config) # Default to OpenAI (most compatible)
        end
      end
    end
  end
end
