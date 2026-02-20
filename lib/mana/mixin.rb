# frozen_string_literal: true

module Mana
  # Include in classes to use ~"..." in instance methods
  # and `mana def` for LLM-compiled methods.
  module Mixin
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Mark a method for LLM compilation.
      # Usage:
      #   mana def fizzbuzz(n)
      #     ~"return FizzBuzz array from 1 to n"
      #   end
      def mana(method_name)
        Mana::Compiler.compile(self, method_name)
        method_name
      end
    end
  end
end

# Make `mana def` available at the top level (main object)
class << self
  def mana(method_name)
    Mana::Compiler.compile(Object, method_name)
    method_name
  end
end
