# ruby-mana 🔮

Embed LLM as native Ruby. Write natural language, it just runs.

```ruby
require "mana"

numbers = [1, "2", "three", "cuatro", "五"]
~"算 <numbers> 的语义平均值存 <result>"
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

### Two ways to write

**`~"..."` — works in any `.rb` file:**

```ruby
require "mana"

numbers = [1, 2, 3, 4, 5]
~"算 <numbers> 的平均值存 <result>"
puts result
```

**Bare strings — in `.nrb` files:**

```ruby
# math.nrb
numbers = [1, 2, 3, 4, 5]
"算 <numbers> 的平均值存 <result>"
puts result
```

```ruby
# main.rb
require "mana"
Mana.load("math")  # loads math.nrb from same directory
```

### Variables

Use `<var>` to reference variables. Mana figures out read vs write:

- Variable exists in scope → Mana reads it and passes to LLM
- Variable doesn't exist → LLM creates it via `write_var`

```ruby
name = "Alice"
scores = [85, 92, 78, 95, 88]

~"给 <name> 的 <scores> 做个分析，平均分存 <average>，最高分存 <best>，评语存 <comment>"

puts average  # => 87.6
puts best     # => 95
puts comment  # => "成绩优秀，表现稳定"
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

~"读 <email> 的 subject 和 body，设 category 和 priority"

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

~"遍历 <portfolio>，调用 fetch_price 拿价格，价格>200 就 send_alert，总和存 <total>"
puts total  # => 579.6
```

### Mixed control flow

Ruby handles the structure, LLM handles the decisions:

```ruby
player_hp = 100
enemy_hp = 80
inventory = ["sword", "potion", "shield"]

while player_hp > 0 && enemy_hp > 0
  ~"玩家 HP=<player_hp>，敌人 HP=<enemy_hp>，背包=<inventory>，选行动存 <action>"

  case action
  when "attack" then enemy_hp -= rand(15..25)
  when "defend" then nil
  when "use_item"
    ~"从 <inventory> 选一个治疗物品存 <item_name>"
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

# Or shorthand
Mana.model = "claude-sonnet-4-20250514"
```

## How it works

1. `~"..."` calls `String#~@`, which captures the caller's `Binding`
2. Mana parses `<var>` references and reads existing variables as context
3. The prompt + context is sent to the LLM with tools: `read_var`, `write_var`, `read_attr`, `write_attr`, `call_func`, `done`
4. LLM responds with tool calls → Mana executes them against the live Ruby binding → sends results back
5. Loop until LLM calls `done` or returns without tool calls

For `.nrb` files, Prism (Ruby 3.3+ built-in parser) identifies bare string statements in the AST and prepends `~` during load.

## Safety

⚠️ Mana executes LLM-generated operations against your live Ruby state. Use with the same caution as `eval`.

## License

MIT
