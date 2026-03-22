# frozen_string_literal: true

module Mana
  class Config
    attr_accessor :model, :temperature, :api_key, :max_iterations, :base_url,
                  :backend, :timeout,
                  :namespace, :memory_store, :memory_path,
                  :context_window, :memory_pressure, :memory_keep_recent,
                  :compact_model, :on_compact

    DEFAULT_ANTHROPIC_URL = "https://api.anthropic.com"
    DEFAULT_OPENAI_URL = "https://api.openai.com"

    def initialize
      @model = "claude-sonnet-4-20250514"
      @temperature = 0
      @api_key = ENV["ANTHROPIC_API_KEY"] || ENV["OPENAI_API_KEY"]
      @max_iterations = 50
      @base_url = ENV["ANTHROPIC_API_URL"] || ENV["OPENAI_API_URL"]
      @timeout = 30
      @backend = nil
      @namespace = nil
      @memory_store = nil
      @memory_path = nil
      @context_window = nil
      @memory_pressure = 0.7
      @memory_keep_recent = 4
      @compact_model = nil
      @on_compact = nil
    end

    # Resolve the effective base URL based on the configured or auto-detected backend.
    # Falls back to the appropriate default when no explicit URL is set.
    def effective_base_url
      return @base_url if @base_url

      if anthropic_backend?
        DEFAULT_ANTHROPIC_URL
      else
        DEFAULT_OPENAI_URL
      end
    end

    private

    def anthropic_backend?
      case @backend&.to_s
      when "anthropic" then true
      when "openai" then false
      else @model.match?(Backends::ANTHROPIC_PATTERNS)
      end
    end
  end
end
