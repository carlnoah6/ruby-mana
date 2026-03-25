# frozen_string_literal: true

require "mana"

module Mana
  module TestHelpers
    # Auto-enable mock mode before each test, disable after
    def self.included(base)
      base.before { Mana.mock! }
      base.after { Mana.unmock! }
    end

    # Convenience method to register a stub within the current mock context
    def mock_prompt(pattern, **values, &block)
      raise Mana::MockError, "Mana mock mode not active. Call Mana.mock! first" unless Mana.mock_active?

      Mana.current_mock.prompt(pattern, **values, &block)
    end
  end
end
