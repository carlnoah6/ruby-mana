# frozen_string_literal: true

# Example: Function discovery — LLM discovers and calls your Ruby functions
require "mana"

# Look up the price of a stock symbol
# @param symbol [String] the ticker symbol
def lookup_price(symbol:)
  prices = { "AAPL" => 189.5, "GOOG" => 141.2, "TSLA" => 248.9 }
  prices[symbol] || "unknown symbol: #{symbol}"
end

# Send an email notification
# @param to [String] recipient email
# @param subject [String] email subject
# @param body [String] email body
def send_email(to:, subject:, body:)
  puts "[EMAIL] To: #{to}, Subject: #{subject}"
  puts "  #{body}"
  "sent"
end

# Use them in prompts — LLM discovers functions from comments
~"get the current time using Time.now and store in <current_time>"
puts "Time: #{current_time}"

portfolio = ["AAPL", "GOOG", "TSLA"]
~"look up prices for each symbol in <portfolio> using lookup_price, store total in <total>"
puts "Portfolio total: $#{total}"

~"send an email to user@example.com about the portfolio value using send_email"
