# frozen_string_literal: true

require "binding_of_caller"

class String
  # ~"natural language prompt" → execute via Mana engine
  def ~@
    return self if Thread.current[:mana_running]

    Thread.current[:mana_running] = true
    begin
      Mana::Engine.run(self, binding.of_caller(1))
    ensure
      Thread.current[:mana_running] = false
    end
  end
end
