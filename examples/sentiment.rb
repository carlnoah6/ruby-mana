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
  ~"analyze the sentiment of this review: '#{review}'. Store sentiment as positive/neutral/negative in <sentiment>, and confidence as a float 0-1 in <confidence>"
  results << { text: review, sentiment: sentiment, confidence: confidence }
end

results.each do |r|
  puts "#{r[:sentiment].upcase.ljust(10)} (#{r[:confidence]}) #{r[:text][0..50]}..."
end

~"based on <results>, write a brief summary and store in <summary>"
puts "\n#{summary}"
