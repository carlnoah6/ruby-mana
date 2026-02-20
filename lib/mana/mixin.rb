# frozen_string_literal: true

module Mana
  # Include in classes to use ~"..." in instance methods.
  # binding_of_caller handles scope automatically, so this
  # is mainly a semantic marker + future extension point.
  module Mixin
    def self.included(base)
      # Reserved for future: auto-expose methods, etc.
    end
  end
end
