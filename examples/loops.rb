# frozen_string_literal: true

# Example: LLM loops and calls Ruby functions
require "mana"

def fetch_price(symbol)
  { "AAPL" => 189.5, "GOOG" => 141.2, "TSLA" => 248.9 }[symbol] || 0
end

def send_alert(msg)
  puts "[ALERT] #{msg}"
end

portfolio = ["AAPL", "GOOG", "TSLA", "MSFT"]

~"遍历 <portfolio>，对每个 symbol 调用 fetch_price 拿价格。价格>200 就 send_alert，价格==0 也 send_alert。有效价格总和存 <total>"

puts "Total: #{total}"
