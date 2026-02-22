require "mana"

Mana.configure do |c|
  c.api_key = ENV["ANTHROPIC_API_KEY"]
  c.model = "claude-sonnet-4-20250514"
end

puts "=== JavaScript ==="
data = [1, 2, 3, 4, 5]
~"const evens = data.filter(n => n % 2 === 0)"
puts "Evens: #{evens}"

~"const sum = evens.reduce((a, b) => a + b, 0)"
puts "Sum: #{sum}"

puts "\n=== Natural Language (LLM) ==="
text = "The quick brown fox jumps over the lazy dog"
~"count the words in <text>, store the count in <word_count>"
puts "Word count: #{word_count}"

puts "\n=== Mixed ==="
numbers = [10, 20, 30, 40, 50]
~"const doubled = numbers.map(n => n * 2)"
puts "Doubled (JS): #{doubled}"

~"analyze <doubled> and tell me the statistical properties, store summary in <stats>"
puts "Stats (LLM): #{stats}"
