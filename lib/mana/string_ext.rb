# frozen_string_literal: true

require "binding_of_caller"

class String
  # ~"natural language prompt" → execute via Mana engine
  def ~@
    Mana::Engine.run(self, binding.of_caller(1))
  end
end
