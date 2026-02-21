# frozen_string_literal: true

module Mana
  class Config
    attr_accessor :model, :temperature, :api_key, :max_iterations, :base_url,
                  :backend,
                  :namespace, :memory_store, :memory_path,
                  :context_window, :memory_pressure, :memory_keep_recent,
                  :compact_model, :on_compact

    def initialize
      @model = "claude-sonnet-4-20250514"
      @temperature = 0
      @api_key = ENV["ANTHROPIC_API_KEY"]
      @max_iterations = 50
      @base_url = "https://api.anthropic.com"
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
  end
end
