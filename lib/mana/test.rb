# frozen_string_literal: true

require "mana"

module Mana
  module TestHelpers
    def self.included(base)
      base.before { Mana.mock! }
      base.after { Mana.unmock! }
    end

    def mock_prompt(pattern, **values, &block)
      raise Mana::MockError, "Mana mock mode not active. Call Mana.mock! first" unless Mana.mock_active?

      Mana.current_mock.prompt(pattern, **values, &block)
    end
  end
end
