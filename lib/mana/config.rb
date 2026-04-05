# frozen_string_literal: true

module Mana
  # Central configuration for Mana. Set via Mana.configure { |c| ... }.
  #
  # Key options:
  #   model            - LLM model name (default: claude-sonnet-4-6)
  #   api_key          - API key, falls back to ANTHROPIC_API_KEY or OPENAI_API_KEY env vars
  #   base_url         - Custom API endpoint, falls back to ANTHROPIC_API_URL or OPENAI_API_URL
  #   backend          - :anthropic, :openai, or nil (auto-detect from model name)
  #   timeout          - HTTP timeout in seconds (default: 120)
  class Config
    attr_accessor :model, :temperature, :api_key, :max_iterations, :base_url,
                  :backend, :verbose,
                  :namespace, :memory_store, :memory_path,
                  :context_window,
                  :context_class, :knowledge_provider
    attr_reader :timeout

    # Backward compatibility aliases
    alias_method :memory_class, :context_class
    alias_method :memory_class=, :context_class=

    DEFAULT_ANTHROPIC_URL = "https://api.anthropic.com"
    DEFAULT_OPENAI_URL = "https://api.openai.com"

    # All config options can be set via environment variables:
    #   MANA_MODEL, MANA_VERBOSE, MANA_TIMEOUT, MANA_BACKEND
    #   ANTHROPIC_API_KEY / OPENAI_API_KEY
    #   ANTHROPIC_API_URL / OPENAI_API_URL
    def initialize
      @model = ENV["MANA_MODEL"] || "claude-sonnet-4-6"
      @temperature = 0
      @api_key = ENV["ANTHROPIC_API_KEY"] || ENV["OPENAI_API_KEY"]
      @max_iterations = 50
      @base_url = ENV["ANTHROPIC_API_URL"] || ENV["OPENAI_API_URL"]
      self.timeout = (ENV["MANA_TIMEOUT"] || 120).to_i
      @verbose = %w[1 true yes].include?(ENV["MANA_VERBOSE"]&.downcase)
      @backend = ENV["MANA_BACKEND"]&.to_sym
      @namespace = nil
      @memory_store = nil
      @memory_path = nil
      @context_window = 128_000
      @context_class = nil         # nil = use Mana::Context; set to custom class
      @knowledge_provider = nil    # nil = use Mana::Knowledge; set to custom module with .query(topic)
    end

    # Set timeout; must be a positive number
    def timeout=(value)
      unless value.is_a?(Numeric) && value.positive?
        raise ArgumentError, "timeout must be a positive number, got #{value.inspect}"
      end

      @timeout = value
    end

    # Resolve the effective base URL based on the configured or auto-detected backend.
    # Falls back to the appropriate default when no explicit URL is set.
    def effective_base_url
      # Return user-configured URL if explicitly set
      return @base_url if @base_url

      # Otherwise pick the default URL based on backend type
      if anthropic_backend?
        DEFAULT_ANTHROPIC_URL
      else
        DEFAULT_OPENAI_URL
      end
    end

    # Validate configuration and raise early if something is wrong.
    # Called automatically by Mana.configure, or manually via Mana.config.validate!
    def validate!
      if @api_key.nil? || @api_key.to_s.strip.empty?
        raise ConfigError,
          "API key is not configured. Set it via environment variable or Mana.configure:\n\n" \
          "  export ANTHROPIC_API_KEY=your_key_here\n" \
          "  # or\n" \
          "  export OPENAI_API_KEY=your_key_here\n" \
          "  # or\n" \
          "  Mana.configure { |c| c.api_key = \"your_key_here\" }\n"
      end
      true
    end

    private

    # Determine whether the current backend is Anthropic
    def anthropic_backend?
      case @backend&.to_s
      when "anthropic" then true
      when "openai" then false
      # No explicit backend; auto-detect from model name pattern
      else @model.match?(Backends::Base::ANTHROPIC_PATTERN)
      end
    end
  end
end
