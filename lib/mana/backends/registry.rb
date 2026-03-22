# frozen_string_literal: true

module Mana
  module Backends
    # Model name patterns used to auto-detect which backend to use.
    ANTHROPIC_PATTERNS = /^(claude-)/i
    OPENAI_PATTERNS = /^(gpt-|o1-|o3-|chatgpt-|dall-e|tts-|whisper-)/i

    # Resolve a backend instance from configuration.
    # Priority: explicit backend instance > backend name > auto-detect from model name.
    # Falls back to OpenAI as the most widely compatible format.
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
