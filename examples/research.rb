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

~"用 search_db 查询 <languages> 里每种语言的信息。
  用 calculate 算出它们的平均创建年份。
  按创建时间排序，写一段比较分析存 <analysis>。
  最老的语言存 <oldest>，最新的存 <newest>"

puts "Oldest: #{oldest}"
puts "Newest: #{newest}"
puts "\n#{analysis}"
