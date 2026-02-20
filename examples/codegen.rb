# frozen_string_literal: true

# Example: Code generation — LLM writes Ruby code, Ruby evals it
require "mana"

# Describe a function in natural language, LLM writes the implementation
~"write a Ruby method fizzbuzz(n) that returns an array of FizzBuzz results from 1 to n. Store the code in <code>"

eval(code) # rubocop:disable Security/Eval
puts fizzbuzz(15).inspect
# => ["1", "2", "Fizz", "4", "Buzz", "Fizz", "7", "8", "Fizz", "Buzz", "11", "Fizz", "13", "14", "FizzBuzz"]

# Generate a data transformation pipeline
data = [
  { name: "Alice", age: 30, salary: 80_000 },
  { name: "Bob", age: 25, salary: 60_000 },
  { name: "Charlie", age: 35, salary: 120_000 },
  { name: "Diana", age: 28, salary: 95_000 }
]

~"look at <data> structure, write Ruby code that filters salary > 70000, sorts by age, and returns an array of names. Store in <transform_code>"

result = eval(transform_code) # rubocop:disable Security/Eval
puts result.inspect
# => ["Diana", "Alice", "Charlie"]
