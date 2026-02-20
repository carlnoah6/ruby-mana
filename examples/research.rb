# frozen_string_literal: true

# Example: Multi-step reasoning — LLM plans and executes a research task
require "mana"

def search_db(query)
  # Simulated database
  db = {
    "ruby" => { created: 1995, creator: "Matz", type: "dynamic" },
    "python" => { created: 1991, creator: "Guido", type: "dynamic" },
    "rust" => { created: 2010, creator: "Graydon Hoare", type: "static" },
    "go" => { created: 2009, creator: "Rob Pike et al.", type: "static" }
  }
  db[query.downcase]
end

def calculate(expression)
  eval(expression).to_f # rubocop:disable Security/Eval
end

languages = ["Ruby", "Python", "Rust", "Go"]

~"use search_db to look up each language in <languages>.
  use calculate to compute their average creation year.
  sort them by creation year, write a comparative analysis and store in <analysis>.
  store the oldest language name in <oldest> and the newest in <newest>"

puts "Oldest: #{oldest}"
puts "Newest: #{newest}"
puts "\n#{analysis}"
