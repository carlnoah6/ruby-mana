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

puts "\n=== Python ==="
data = [1, 2, 3, 4, 5]
~"evens = [n for n in data if n % 2 == 0]"
puts "Evens (Python): #{evens}"

~"total = sum(evens)"
puts "Sum (Python): #{total}"

puts "\n=== Bidirectional: Python calls Ruby ==="

# Define a Ruby method that Python can call back
class Converter
  def celsius_to_fahrenheit(c)
    c * 9.0 / 5 + 32
  end
end

converter = Converter.new
~"temps_c = [0, 20, 37, 100]"
~"temps_f = [converter.celsius_to_fahrenheit(c) for c in temps_c]"
puts "Fahrenheit: #{temps_f}"

# Ruby proc callable from Python
doubler = proc { |x| x * 2 }
~"result = [doubler(n) for n in [1, 2, 3, 4]]"
puts "Doubled via Ruby proc: #{result}"

# Python reads/writes Ruby variables via bridge
score = 0
~"ruby.write('score', ruby.read('score') + 100)"
puts "Score after Python update: #{score}"

puts "\n=== Bidirectional: JS calls Ruby ==="

# Define a Ruby method that JS can call
def celsius_to_fahrenheit(c)
  c * 9.0 / 5 + 32
end

# JS calls Ruby method, uses result in JS computation
~"const temps_c2 = [0, 20, 37, 100]"
~"const temps_f2 = temps_c2.map(c => ruby.celsius_to_fahrenheit(c))"
puts "Fahrenheit (JS): #{temps_f2}"

# Define a Mana effect (custom tool) callable from JS
Mana.define_effect :fetch_price, description: "Get item price" do |item:|
  prices = { "apple" => 1.5, "banana" => 0.75, "cherry" => 3.0 }
  prices[item] || 0
end

~"const total = ruby.fetch_price('apple') + ruby.fetch_price('banana')"
puts "Total price: $#{total}"

# JS reads/writes Ruby variables dynamically
js_score = 0
~"ruby.write('js_score', ruby.read('js_score') + 100)"
puts "Score after JS update: #{js_score}"
