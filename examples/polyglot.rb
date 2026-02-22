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

puts "\n=== Bidirectional: JS calls Ruby ==="

# Define a Ruby method that JS can call
def celsius_to_fahrenheit(c)
  c * 9.0 / 5 + 32
end

# JS calls Ruby method, uses result in JS computation
~"const temps_c = [0, 20, 37, 100]"
~"const temps_f = temps_c.map(c => ruby.celsius_to_fahrenheit(c))"
puts "Fahrenheit: #{temps_f}"

# Define a Mana effect (custom tool) callable from JS
Mana.define_effect :fetch_price, description: "Get item price" do |item:|
  prices = { "apple" => 1.5, "banana" => 0.75, "cherry" => 3.0 }
  prices[item] || 0
end

~"const total = ruby.fetch_price('apple') + ruby.fetch_price('banana')"
puts "Total price: $#{total}"

# JS reads/writes Ruby variables dynamically
score = 0
~"ruby.write('score', ruby.read('score') + 100)"
puts "Score after JS update: #{score}"
