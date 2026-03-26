# frozen_string_literal: true

# Example: Configuration — how to set up Mana for different LLM providers
require "mana"

# --- Option 1: Environment variables (recommended) ---
# Set these in your .env file or shell:
#   export ANTHROPIC_API_KEY=sk-your-key
#   export ANTHROPIC_API_URL=https://api.anthropic.com  # optional
#   export MANA_MODEL=claude-sonnet-4-6
#   export MANA_VERBOSE=true
#   export MANA_SECURITY=standard

# --- Option 2: Programmatic configuration ---
Mana.configure do |c|
  # LLM settings
  c.model = "claude-sonnet-4-6"          # or "gpt-4o", "llama3", etc.
  c.api_key = ENV["ANTHROPIC_API_KEY"]
  c.timeout = 120                         # HTTP timeout in seconds
  c.verbose = true                        # show LLM interactions in stderr

  # Security level (0-4)
  c.security = :standard                  # level 2: allows File.read, Dir.glob
  # Fine-grained overrides:
  # c.security.allow_receiver "File", only: %w[read exist?]
  # c.security.block_method "puts"

  # Memory settings
  c.memory_pressure = 0.7                 # compact when tokens > 70% of window
  c.memory_keep_recent = 4                # keep last 4 rounds during compaction
end

# --- Switching to OpenAI ---
# Mana.configure do |c|
#   c.api_key = ENV["OPENAI_API_KEY"]
#   c.base_url = "https://api.openai.com"
#   c.model = "gpt-4o"
# end

# --- Switching to Ollama (local) ---
# Mana.configure do |c|
#   c.api_key = "unused"
#   c.base_url = "http://localhost:11434"
#   c.model = "llama3"
# end

# --- Switching to Groq ---
# Mana.configure do |c|
#   c.backend = :openai
#   c.api_key = ENV["GROQ_API_KEY"]
#   c.base_url = "https://api.groq.com/openai"
#   c.model = "llama-3.3-70b-versatile"
# end

# Test the configuration
~"what is 2 + 2? store in <result>"
puts "Result: #{result}"
