# frozen_string_literal: true

# Example: Translation pipeline — LLM as a multilingual processor
require "mana"

menu_items = [
  { dish: "Kung Pao Chicken", price: 38 },
  { dish: "Mapo Tofu", price: 28 },
  { dish: "Braised Pork Belly", price: 45 },
  { dish: "Steamed Sea Bass", price: 68 }
]

translations = {}

menu_items.each do |item|
  dish = item[:dish]
  ~"translate the dish name '#{dish}' to French and store in <french>, to Japanese and store in <japanese>, and write a one-line description in <description>"
  translations[dish] = { fr: french, ja: japanese, desc: description, price: item[:price] }
end

puts "=" * 70
puts "MENU"
puts "=" * 70
translations.each do |en, info|
  puts "\n#{en} / #{info[:fr]} / #{info[:ja]}"
  puts "  $#{info[:price]} — #{info[:desc]}"
end
