# frozen_string_literal: true

# Example: Testing with Mana.mock — no API calls needed
require "mana"

# --- Block mode: inline tests ---
Mana.mock do
  # Register stubs: each key becomes a local variable
  prompt "analyze", bugs: ["XSS", "SQL injection"], score: 7.5

  code = "user_input = params[:name]"
  ~"analyze <code> for security issues, store bugs in <bugs> and score in <score>"
  puts "Bugs: #{bugs.inspect}"   # => ["XSS", "SQL injection"]
  puts "Score: #{score}"          # => 7.5
end

# --- Block mode with _return ---
Mana.mock do
  prompt "translate", _return: "你好世界"

  result = ~"translate 'hello world' to Chinese"
  puts "Translation: #{result}"   # => "你好世界"
end

# --- Dynamic stubs with blocks ---
Mana.mock do
  prompt(/translate.*to\s+(\w+)/) do |prompt_text|
    lang = prompt_text.match(/to\s+(\w+)/)[1]
    { output: "translated to #{lang}" }
  end

  ~"translate hello to Japanese, store in <output>"
  puts "Dynamic: #{output}"       # => "translated to Japanese"
end

# --- RSpec integration ---
# In your spec_helper.rb:
#
#   require "mana"
#   RSpec.configure do |config|
#     config.include Mana::TestHelpers, :mana
#   end
#
# In your spec file:
#
#   describe MyApp, :mana do
#     it "analyzes code" do
#       mock_prompt "analyze", bugs: ["XSS"]
#       result = MyApp.analyze("input")
#       expect(result[:bugs]).to include("XSS")
#     end
#   end

puts "\nAll mock examples passed!"
