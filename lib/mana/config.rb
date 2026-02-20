# frozen_string_literal: true

module Mana
  class Config
    attr_accessor :model, :temperature, :api_key, :max_iterations, :base_url

    def initialize
      @model = "claude-sonnet-4-20250514"
      @temperature = 0
      @api_key = ENV["ANTHROPIC_API_KEY"]
      @max_iterations = 50
      @base_url = "https://api.anthropic.com"
    end
  end
end
