# frozen_string_literal: true

# Example: Translation pipeline — LLM as a multilingual processor
require "mana"

menu_items = [
  { dish: "宫保鸡丁", price: 38 },
  { dish: "麻婆豆腐", price: 28 },
  { dish: "红烧肉", price: 45 },
  { dish: "清蒸鲈鱼", price: 68 }
]

translations = {}

menu_items.each do |item|
  dish = item[:dish]
  ~"translate the dish name '#{dish}' to English and store in <english>, to Japanese and store in <japanese>, and write a one-line English description in <description>"
  translations[dish] = { en: english, ja: japanese, desc: description, price: item[:price] }
end

puts "=" * 70
puts "MENU / メニュー / 菜单"
puts "=" * 70
translations.each do |cn, info|
  puts "\n#{cn} / #{info[:en]} / #{info[:ja]}"
  puts "  ¥#{info[:price]} — #{info[:desc]}"
end
