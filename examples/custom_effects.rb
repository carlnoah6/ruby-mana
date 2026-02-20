# frozen_string_literal: true

# Example: Custom effect handlers
require "mana"

# Define a custom effect — no params
Mana.define_effect :get_time,
  description: "Get the current date and time" do
    Time.now.strftime("%Y-%m-%d %H:%M:%S")
  end

# Define a custom effect — with params
Mana.define_effect :lookup_price,
  description: "Look up the price of a stock symbol" do |symbol:|
    prices = { "AAPL" => 189.5, "GOOG" => 141.2, "TSLA" => 248.9 }
    prices[symbol] || "unknown symbol: #{symbol}"
  end

# Define a custom effect — multiple params
Mana.define_effect :send_email,
  description: "Send an email notification" do |to:, subject:, body:|
    puts "[EMAIL] To: #{to}, Subject: #{subject}"
    puts "  #{body}"
    "sent"
  end

# Use them in prompts
~"get the current time and store it in <current_time>"
puts "Time: #{current_time}"

portfolio = ["AAPL", "GOOG", "TSLA"]
~"look up prices for each symbol in <portfolio> using lookup_price, store total in <total>"
puts "Portfolio total: $#{total}"

~"send an email to user@example.com about the portfolio value using send_email"
