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

~"iterate <portfolio>, call fetch_price for each symbol. If price > 200 call send_alert, if price == 0 also send_alert. Store the sum of valid prices in <total>"

puts "Total: #{total}"
