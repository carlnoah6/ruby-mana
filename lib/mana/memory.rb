# frozen_string_literal: true

module Mana
  class Memory
    attr_reader :short_term, :long_term, :summaries

    # Initialize with empty short-term and load persisted long-term memories from disk
    def initialize
      @short_term = []
      @long_term = []
      @summaries = []
      @next_id = 1
      @compact_mutex = Mutex.new
      @compact_thread = nil
      load_long_term
    end

    # --- Class methods ---

    class << self
      # Return the current thread's memory instance (lazy-initialized).
      # Returns nil in incognito mode.
      def current
        return nil if incognito?

        Thread.current[:mana_memory] ||= new
      end

      # Check if the current thread is in incognito mode (no memory)
      def incognito?
        Thread.current[:mana_incognito] == true
      end

      # Run a block with memory disabled. Saves and restores previous state.
      def incognito(&block)
        previous_memory = Thread.current[:mana_memory]
        previous_incognito = Thread.current[:mana_incognito]
        Thread.current[:mana_incognito] = true
        Thread.current[:mana_memory] = nil
        block.call
      # Always restore previous state, even if the block raises
      ensure
        Thread.current[:mana_incognito] = previous_incognito
        Thread.current[:mana_memory] = previous_memory
      end
    end

    # --- Token estimation ---

    # Estimate total token count across short-term messages, long-term facts, and summaries.
    # Used to determine when memory compaction is needed.
    def token_count
      count = 0
      @short_term.each do |msg|
        content = msg[:content]
        case content
        when String
          # Plain text message
          count += estimate_tokens(content)
        when Array
          # Array of content blocks (tool_use, tool_result, text)
          content.each do |block|
            count += estimate_tokens(block[:text] || block[:content] || "")
          end
        end
      end
      @long_term.each { |m| count += estimate_tokens(m[:content]) }
      @summaries.each { |s| count += estimate_tokens(s) }
      count
    end

    # --- Memory management ---

    # Clear both short-term and long-term memory
    def clear!
      clear_short_term!
      clear_long_term!
    end

    # Clear conversation history and compaction summaries
    def clear_short_term!
      @short_term.clear
      @summaries.clear
    end

    # Clear persistent memories from both in-memory array and disk
    def clear_long_term!
      @long_term.clear
      store.clear(namespace)
    end

    # Remove a specific long-term memory by ID and persist the change
    def forget(id:)
      @long_term.reject! { |m| m[:id] == id }
      store.write(namespace, @long_term)
    end

    # Store a fact in long-term memory. Deduplicates by content.
    # Persists to disk immediately after adding.
    def remember(content)
      # Deduplicate: skip if identical content already exists
      existing = @long_term.find { |e| e[:content] == content }
      return existing if existing

      entry = { id: @next_id, content: content, created_at: Time.now.iso8601 }
      @next_id += 1
      @long_term << entry
      store.write(namespace, @long_term)
      entry
    end

    # --- Compaction ---

    # Synchronous compaction: wait for any background run, then compact immediately
    def compact!
      wait_for_compaction
      perform_compaction
    end

    # Check if token usage exceeds the configured memory pressure threshold
    def needs_compaction?
      cw = context_window
      token_count > (cw * Mana.config.memory_pressure)
    end

    # Launch background compaction if token pressure exceeds the threshold.
    # Only one compaction thread runs at a time (guarded by mutex).
    def schedule_compaction
      return unless needs_compaction?

      @compact_mutex.synchronize do
        # Skip if a compaction is already in progress
        return if @compact_thread&.alive?

        @compact_thread = Thread.new do
          perform_compaction
        rescue => e
          # Silently handle compaction errors — don't crash the main thread
          $stderr.puts "Mana compaction error: #{e.message}" if $DEBUG
        end
      end
    end

    # Block until the background compaction thread finishes (if running)
    def wait_for_compaction
      thread = @compact_mutex.synchronize { @compact_thread }
      thread&.join
    end

    # --- Display ---

    # Human-readable summary: counts and token usage
    def inspect
      "#<Mana::Memory long_term=#{@long_term.size}, short_term=#{short_term_rounds} rounds, tokens=#{token_count}/#{context_window}>"
    end

    private

    # Count conversation rounds (user-prompt messages only, not tool results)
    def short_term_rounds
      @short_term.count { |m| m[:role] == "user" && m[:content].is_a?(String) }
    end

    # Rough token estimate: ~4 characters per token
    def estimate_tokens(text)
      return 0 unless text.is_a?(String)

      (text.length / 4.0).ceil
    end

    # Resolve context window size: user config > auto-detect from model name
    def context_window
      Mana.config.context_window || ContextWindow.detect(Mana.config.model)
    end

    # Resolve memory store: user config > default file-based store
    def store
      Mana.config.memory_store || default_store
    end

    # Lazy-initialized default FileStore singleton
    def default_store
      @default_store ||= FileStore.new
    end

    # Resolve namespace for memory isolation
    def namespace
      Namespace.detect
    end

    # Load long-term memories from the persistent store on initialization.
    # Skips loading in incognito mode.
    def load_long_term
      return if self.class.incognito?

      @long_term = store.read(namespace)
      # Set next ID to one past the highest existing ID
      @next_id = (@long_term.map { |m| m[:id] }.max || 0) + 1
    end

    # Compact short-term memory: summarize old messages and keep only recent rounds.
    # This reduces token count while preserving key context.
    def perform_compaction
      keep_recent = Mana.config.memory_keep_recent
      # Find indices of user-prompt messages (each marks a conversation round)
      user_indices = @short_term.each_with_index
        .select { |msg, _| msg[:role] == "user" && msg[:content].is_a?(String) }
        .map(&:last)

      # Not enough rounds to compact — nothing to do
      return if user_indices.size <= keep_recent

      # Find the cutoff point: everything before the last N rounds gets summarized
      # Clamp keep_recent to avoid negative index beyond array bounds
      keep = [keep_recent, user_indices.size].min
      cutoff_user_idx = user_indices[-keep]
      old_messages = @short_term[0...cutoff_user_idx]
      return if old_messages.empty?

      # Build text from old messages for summarization
      text_parts = old_messages.map do |msg|
        content = msg[:content]
        case content
        when String then "#{msg[:role]}: #{content}"
        when Array
          texts = content.map { |b| b[:text] || b[:content] }.compact
          "#{msg[:role]}: #{texts.join(' ')}" unless texts.empty?
        end
      end.compact

      return if text_parts.empty?

      # Call the LLM to summarize the old conversation
      summary = summarize(text_parts.join("\n"))

      # Replace old messages with the summary, keeping only recent rounds
      @short_term = @short_term[cutoff_user_idx..]
      @summaries << summary

      # Notify the on_compact callback if configured
      Mana.config.on_compact&.call(summary)
    end

    # Call the LLM to produce a concise summary of the given conversation text.
    # Uses the configured backend (Anthropic/OpenAI), respects timeout settings.
    # Falls back to "Summary unavailable" on any error.
    def summarize(text)
      config = Mana.config
      model = config.compact_model || config.model
      backend = Mana::Backends.for(config)

      content = backend.chat(
        system: "Summarize this conversation concisely. Preserve key facts, decisions, and context.",
        messages: [{ role: "user", content: text }],
        tools: [],
        model: model,
        max_tokens: 1024
      )

      return "Summary unavailable" unless content.is_a?(Array)

      content.map { |b| b[:text] || b["text"] }.compact.join("\n")
    rescue => _e
      "Summary unavailable"
    end
  end
end
