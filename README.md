# ruby-mana 🔮

Embed LLM as native Ruby. Write natural language, it just runs.

```ruby
require "mana"

numbers = [1, "2", "three", "cuatro", "五"]
~"compute the semantic average of <numbers> and store in <result>"
puts result  # => 3.0
```

## What is this?

Mana turns LLM into a Ruby co-processor. Your natural language strings can read and write Ruby variables, call Ruby functions, manipulate objects, and control program flow — all from a single `~"..."`.

Not an API wrapper. Not prompt formatting. Mana weaves LLM into your Ruby code as a first-class construct.

## Install

```bash
gem install ruby-mana
```

Or in your Gemfile:

```ruby
gem "ruby-mana"
```

Requires Ruby 3.3+ and an Anthropic API key:

```bash
export ANTHROPIC_API_KEY=your_key_here
```

## Usage

Prefix any string with `~` to make it an LLM prompt:

```ruby
require "mana"

numbers = [1, 2, 3, 4, 5]
~"compute the average of <numbers> and store in <result>"
puts result
```

### Variables

Use `<var>` to reference variables. Mana figures out read vs write:

- Variable exists in scope → Mana reads it and passes to LLM
- Variable doesn't exist → LLM creates it via `write_var`

```ruby
name = "Alice"
scores = [85, 92, 78, 95, 88]

~"analyze <scores> for <name>, store the mean in <average>, the highest in <best>, and a short comment in <comment>"

puts average  # => 87.6
puts best     # => 95
puts comment  # => "Excellent and consistent performance"
```

### Object manipulation

LLM can read and write object attributes:

```ruby
class Email
  attr_accessor :subject, :body, :category, :priority
end

email = Email.new
email.subject = "URGENT: Server down"
email.body = "Database connection pool exhausted..."

~"read <email> subject and body, then set its category and priority"

puts email.category  # => "urgent"
puts email.priority   # => "high"
```

### Calling Ruby functions

LLM can call functions in your scope:

```ruby
def fetch_price(symbol)
  { "AAPL" => 189.5, "GOOG" => 141.2, "TSLA" => 248.9 }[symbol] || 0
end

def send_alert(msg)
  puts "[ALERT] #{msg}"
end

portfolio = ["AAPL", "GOOG", "TSLA", "MSFT"]

~"iterate <portfolio>, call fetch_price for each, send_alert if price > 200, store the sum in <total>"
puts total  # => 579.6
```

### Mixed control flow

Ruby handles the structure, LLM handles the decisions:

```ruby
player_hp = 100
enemy_hp = 80
inventory = ["sword", "potion", "shield"]

while player_hp > 0 && enemy_hp > 0
  ~"player HP=<player_hp>, enemy HP=<enemy_hp>, inventory=<inventory>, choose an action and store in <action>"

  case action
  when "attack" then enemy_hp -= rand(15..25)
  when "defend" then nil
  when "use_item"
    ~"pick a healing item from <inventory> and store its name in <item_name>"
    inventory.delete(item_name)
    player_hp += 25
  end

  player_hp -= action == "defend" ? rand(5..10) : rand(10..20)
end
```

## Configuration

```ruby
Mana.configure do |c|
  c.model = "claude-sonnet-4-20250514"
  c.temperature = 0
  c.api_key = ENV["ANTHROPIC_API_KEY"]
  c.max_iterations = 50
end
```

### Custom effect handlers

Define your own tools that the LLM can call. Each effect becomes an LLM tool automatically — the block's keyword parameters define the tool's input schema.

```ruby
# No params
Mana.define_effect :get_time do
  Time.now.to_s
end

# With params — keyword args become tool parameters
Mana.define_effect :query_db do |sql:|
  ActiveRecord::Base.connection.execute(sql).to_a
end

# With description (optional, recommended)
Mana.define_effect :search_web,
  description: "Search the web for information" do |query:, max_results: 5|
    WebSearch.search(query, limit: max_results)
  end

# Use in prompts
~"get the current time and store in <now>"
~"find recent orders using query_db, store in <orders>"
```

Built-in effects (`read_var`, `write_var`, `read_attr`, `write_attr`, `call_func`, `done`) are reserved and cannot be overridden.

# Or shorthand
Mana.model = "claude-sonnet-4-20250514"
```

### LLM-compiled methods

`mana def` lets LLM generate a method implementation on first call. The generated code is cached as a real `.rb` file — subsequent calls are pure Ruby with zero API overhead.

```ruby
mana def fizzbuzz(n)
  ~"return an array of FizzBuzz results from 1 to n"
end

fizzbuzz(15)  # first call → LLM generates code → cached → executed
fizzbuzz(20)  # pure Ruby from .mana_cache/fizzbuzz.rb

# View the generated source
puts Mana.source(:fizzbuzz)
# def fizzbuzz(n)
#   (1..n).map do |i|
#     if i % 15 == 0 then "FizzBuzz"
#     elsif i % 3 == 0 then "Fizz"
#     elsif i % 5 == 0 then "Buzz"
#     else i.to_s
#     end
#   end
# end

# Works in classes too
class Converter
  include Mana::Mixin

  mana def celsius_to_fahrenheit(c)
    ~"convert Celsius to Fahrenheit"
  end
end
```

Generated files live in `.mana_cache/` (add to `.gitignore`, or commit them to skip LLM on CI).

## How it works

1. `~"..."` calls `String#~@`, which captures the caller's `Binding`
2. Mana parses `<var>` references and reads existing variables as context
3. The prompt + context is sent to the LLM with tools: `read_var`, `write_var`, `read_attr`, `write_attr`, `call_func`, `done`
4. LLM responds with tool calls → Mana executes them against the live Ruby binding → sends results back
5. Loop until LLM calls `done` or returns without tool calls

## Safety

⚠️ Mana executes LLM-generated operations against your live Ruby state. Use with the same caution as `eval`.

## License

MIT
