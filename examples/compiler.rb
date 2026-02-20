# frozen_string_literal: true

# Example: mana def — LLM compiles methods on first call
require "mana"

# Define a method with natural language — LLM generates the implementation
mana def fizzbuzz(n)
  ~"return an array of FizzBuzz results from 1 to n"
end

# First call triggers LLM compilation → cached to .mana_cache/fizzbuzz.rb
puts fizzbuzz(15).inspect

# View the generated source
puts "\n--- Generated source ---"
puts Mana.source(:fizzbuzz)

# Second call is pure Ruby — zero API overhead
puts "\nfizzbuzz(5) = #{fizzbuzz(5).inspect}"

# Works with classes too
class Converter
  include Mana::Mixin

  mana def celsius_to_fahrenheit(c)
    ~"convert Celsius to Fahrenheit and return the numeric result"
  end

  mana def meters_to_feet(m)
    ~"convert meters to feet and return the numeric result"
  end
end

conv = Converter.new
puts "\n100°C = #{conv.celsius_to_fahrenheit(100)}°F"
puts "1.8m = #{conv.meters_to_feet(1.8)}ft"

puts "\n--- Converter sources ---"
puts Mana.source(:celsius_to_fahrenheit, owner: Converter)
