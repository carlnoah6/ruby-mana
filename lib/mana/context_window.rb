# frozen_string_literal: true

module Mana
  module ContextWindow
    SIZES = {
      /claude-3-5-sonnet/ => 200_000,
      /claude-sonnet-4/ => 200_000,
      /claude-3-5-haiku/ => 200_000,
      /claude-3-opus/ => 200_000,
      /claude-opus-4/ => 200_000,
      /gpt-4o/ => 128_000,
      /gpt-4-turbo/ => 128_000,
      /gpt-3\.5/ => 16_385
    }.freeze

    DEFAULT = 128_000

    def self.detect(model_name)
      return DEFAULT unless model_name

      SIZES.each do |pattern, size|
        return size if model_name.match?(pattern)
      end

      DEFAULT
    end
  end
end
