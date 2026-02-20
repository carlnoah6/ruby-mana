# frozen_string_literal: true

# Example: Code generation — LLM writes Ruby code, Ruby evals it
require "mana"

# Describe a function in natural language, LLM writes the implementation
~"写一个 Ruby 方法 fizzbuzz(n)，返回 1 到 n 的 FizzBuzz 数组。代码存 <code>"

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

~"看 <data> 的结构，写一段 Ruby 代码存 <transform_code>：筛选 salary > 70000 的人，按 age 排序，返回 name 数组"

result = eval(transform_code) # rubocop:disable Security/Eval
puts result.inspect
# => ["Diana", "Alice", "Charlie"]
