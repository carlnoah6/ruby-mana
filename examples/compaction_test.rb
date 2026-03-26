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

LOG_FILE = File.expand_path("compaction_test.log", __dir__)
$log_file = File.open(LOG_FILE, "w")
$log_file.sync = true

at_exit do
  $log_file.close
  puts "Log written to: #{LOG_FILE}"
end

def log(msg)
  line = "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
  puts line
  $log_file.puts line
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
    log "#{label}   summary[#{i}]: #{s}"
  end
end

# --- Configuration ---

Mana.configure do |c|
  c.context_window = 500       # Small but realistic ratio: short prompts ~20t each
  c.memory_pressure = 0.5      # Trigger at 50% (250 tokens) — ~8 rounds to trigger
  c.memory_keep_recent = 2     # Keep only 2 recent rounds

  c.on_compact = ->(summary) do
    log "COMPACTION COMPLETE"
    log "  Summary: #{summary}"
  end
end

log "=" * 60
log "Compaction Test"
log "  context_window=#{Mana.config.context_window}"
log "  memory_pressure=#{Mana.config.memory_pressure}"
log "  memory_keep_recent=#{Mana.config.memory_keep_recent}"
log "  model=#{Mana.config.model}"
log "=" * 60

# --- Short, realistic prompts (like real usage) ---
# Each round generates ~20-40 tokens in short_term.
# With context_window=500 and pressure=0.5, compaction triggers around round 8.

prompts = [
  "What is 2 + 2? Store in <result>",
  "Capital of France? Store in <result>",
  "What is 7 * 8? Store in <result>",
  "Largest planet in our solar system? Store in <result>",
  "What is 100 / 4? Store in <result>",
  "Capital of Japan? Store in <result>",
  "What is 15 + 27? Store in <result>",
  "Who wrote Romeo and Juliet? Store in <result>",
  "What is 9 * 9? Store in <result>",
  "Capital of Germany? Store in <result>",
  "What is 144 / 12? Store in <result>",
  "Fastest land animal? Store in <result>",
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
