# frozen_string_literal: true

module Mana
  module Engines
    # Language detection - stub for now, full implementation in later PR
    def self.detect(code, context: nil)
      # TODO: YAML rules + regex matching + context inference
      # For now, always return LLM
      LLM
    end
  end
end
