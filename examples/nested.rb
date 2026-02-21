# frozen_string_literal: true

# Example: Nested prompts — LLM calling LLM
require "mana"

Mana.configure do |c|
  c.api_key = ENV["ANTHROPIC_API_KEY"]
  c.model = "claude-sonnet-4-20250514"
end

# Lambda style — concise
analyze_point = ->(point) { ~"analyze data point #{point}, identify the root cause, store in <cause>" }

# Equivalent function definition:
# def analyze_point(point)
#   ~"analyze data point #{point}, identify the root cause, store in <cause>"
#   cause
# end

data = [1.2, 5.8, 1.1, 9.7, 1.3]

~"find outliers in <data>, call analyze_point for each outlier, store summary in <report>"
puts report
