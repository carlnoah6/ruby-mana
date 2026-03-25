# frozen_string_literal: true

module Mana
  module Backends
    # Model name patterns used to auto-detect which backend to use.
    ANTHROPIC_PATTERNS = /^(claude-)/i
    OPENAI_PATTERNS = /^(gpt-|o1-|o3-|chatgpt-|dall-e|tts-|whisper-)/i

    # Resolve a backend instance from configuration.
    # Priority: explicit backend instance > backend name > auto-detect from model name.
    # Falls back to OpenAI as the most widely compatible format.
    # Resolve the backend instance from config.
    # Priority: pre-built instance > explicit name > auto-detect from model name.
    def self.for(config)
      # If backend is already an instance, use it directly
      return config.backend if config.backend.is_a?(Anthropic) || config.backend.is_a?(OpenAI)

      # Validate API key before making any requests
      if config.api_key.nil? || config.api_key.to_s.strip.empty?
        raise ConfigError,
          "API key is not configured. Set it via environment variable or Mana.configure:\n\n" \
          "  export ANTHROPIC_API_KEY=your_key_here\n" \
          "  # or\n" \
          "  export OPENAI_API_KEY=your_key_here\n" \
          "  # or\n" \
          "  Mana.configure { |c| c.api_key = \"your_key_here\" }\n"
      end

      # Dispatch by explicit backend name or auto-detect from model name
      case config.backend&.to_s
      when "openai" then OpenAI.new(config)
      when "anthropic" then Anthropic.new(config)
      else
        # Auto-detect from model name; fall back to OpenAI (most compatible)
        case config.model
        when ANTHROPIC_PATTERNS then Anthropic.new(config)
        else OpenAI.new(config)
        end
      end
    end
  end
end
