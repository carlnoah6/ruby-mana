# frozen_string_literal: true

# Compaction test — runs real LLM calls to exercise memory compaction.
# Uses aggressive settings (tiny context window, low pressure threshold)
# so compaction triggers within a few rounds.
#
# Usage:
#   ruby examples/compaction_test.rb
#
# Requires ANTHROPIC_API_KEY (or OPENAI_API_KEY) in the environment.

require "mana"

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def dump_memory(label, memory)
  cw = Mana.config.context_window
  tokens = memory.token_count
  pct = (tokens * 100.0 / cw).round(1)
  log "#{label} tokens=#{tokens}/#{cw} (#{pct}%), needs_compaction=#{memory.needs_compaction?}"
  log "#{label} short_term=#{memory.short_term.size} messages, summaries=#{memory.summaries.size}"

  # Print short_term content summary
  memory.short_term.each_with_index do |msg, i|
    content = msg[:content]
    preview = case content
              when String then content[0, 80]
              when Array then content.map { |b| (b[:text] || b[:content]).to_s[0, 40] }.join(" | ")
              else content.to_s[0, 80]
              end
    log "#{label}   [#{i}] #{msg[:role]}: #{preview}"
  end

  # Print summaries
  memory.summaries.each_with_index do |s, i|
    log "#{label}   summary[#{i}]: #{s[0, 120]}"
  end
end

# --- Configuration ---

Mana.configure do |c|
  c.context_window = 200       # Extremely small — each round ~36 tokens, threshold = 60
  c.memory_pressure = 0.3      # Trigger at 30% usage (60 tokens)
  c.memory_keep_recent = 2     # Keep only 2 recent rounds

  c.on_compact = ->(summary) do
    log "COMPACTION COMPLETE"
    log "  Summary: #{summary[0, 200]}"
  end
end

log "=" * 60
log "Compaction Test"
log "  context_window=#{Mana.config.context_window}"
log "  memory_pressure=#{Mana.config.memory_pressure}"
log "  memory_keep_recent=#{Mana.config.memory_keep_recent}"
log "  model=#{Mana.config.model}"
log "=" * 60

# --- Prompts designed to generate enough tokens ---

prompts = [
  "What is 2 + 2? Store the answer in <result>",
  "What is the capital of France? Store in <result>",
  "List 5 prime numbers under 50 and explain why each is prime. Store the list in <result>",
  "What color is the sky at sunrise, noon, and sunset? Give a detailed answer. Store in <result>",
  "What is 10 * 7? Store the answer in <result>",
]

prompts.each_with_index do |prompt, i|
  round = i + 1
  memory = Mana.memory

  log ""
  log "=== Round #{round} ==="
  dump_memory("BEFORE:", memory)

  log "Prompt: #{prompt.inspect}"
  result = ~prompt
  log "Result: #{result.inspect}"

  # Wait for any background compaction to finish before measuring
  memory.wait_for_compaction

  dump_memory("AFTER: ", memory)
end

log ""
log "=== Final State ==="
memory = Mana.memory
dump_memory("FINAL: ", memory)
log "Done."
