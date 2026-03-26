# frozen_string_literal: true

# Example: YARD comments — help LLM understand your functions
require "mana"

# Without comments, LLM only sees the function signature:
#   search(q) — no description, no type info
#
# With YARD comments, LLM sees:
#   search(q:, limit: ...) — Search products by keyword
#   @param q [String], @param limit [Integer]

# Search products by keyword
# @param q [String] search query
# @param limit [Integer] maximum results to return
def search_products(q:, limit: 5)
  # Simulated product database
  products = [
    { name: "Ruby Programming Book", price: 45.0, category: "books" },
    { name: "Ruby Gemstone Ring", price: 299.0, category: "jewelry" },
    { name: "Ruby Red Shoes", price: 89.0, category: "shoes" },
    { name: "Python Cookbook", price: 39.0, category: "books" },
    { name: "Diamond Necklace", price: 999.0, category: "jewelry" }
  ]
  results = products.select { |p| p[:name].downcase.include?(q.downcase) }
  results.first(limit)
end

# Calculate discount price
# @param price [Float] original price
# @param discount [Float] discount percentage (0-100)
def apply_discount(price:, discount:)
  price * (1 - discount / 100.0)
end

# LLM discovers both functions with descriptions and types
query = "ruby"
~"search_products for <query>, then apply_discount of 20% to the cheapest result, store final price in <final_price>"
puts "Final price: $#{final_price}"
