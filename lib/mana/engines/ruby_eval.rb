# frozen_string_literal: true

module Mana
  module Engines
    class Ruby < Base
      def execute(code)
        eval(code, @binding)
      end
    end
  end
end
