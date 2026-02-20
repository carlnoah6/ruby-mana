# frozen_string_literal: true

# Example: Sentiment analysis on user reviews
require "mana"

reviews = [
  "This product is amazing! Best purchase I've ever made.",
  "Terrible quality. Broke after two days. Want a refund.",
  "It's okay, nothing special. Does what it says.",
  "Absolutely love it! Already bought one for my friend.",
  "Shipping was slow but the product itself is decent."
]

results = []

reviews.each do |review|
  ~"分析这条评论的情感: '#{review}'。存 sentiment 为 positive/neutral/negative，confidence 为 0-1 的浮点数"
  results << { text: review, sentiment: sentiment, confidence: confidence }
end

results.each do |r|
  puts "#{r[:sentiment].upcase.ljust(10)} (#{r[:confidence]}) #{r[:text][0..50]}..."
end

~"根据 <results>，写一段总结存 <summary>"
puts "\n#{summary}"
