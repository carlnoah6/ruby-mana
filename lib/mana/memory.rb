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

    def context_window
      Mana.config.context_window
    end

    # Resolve memory store: user config > default file-based store
    def store
      Mana.config.memory_store || default_store
    end

    # Lazy-initialized default FileStore singleton
    def default_store
      @default_store ||= FileStore.new
    end

    def namespace
      ns = Mana.config.namespace
      return ns if ns && !ns.to_s.empty?

      dir = `git rev-parse --show-toplevel 2>/dev/null`.strip
      return File.basename(dir) unless dir.empty?

      d = Dir.pwd
      loop do
        return File.basename(d) if File.exist?(File.join(d, "Gemfile"))
        parent = File.dirname(d)
        break if parent == d
        d = parent
      end

      File.basename(Dir.pwd)
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
    # Merges existing summaries + old messages into a single new summary, so
    # summaries don't accumulate unboundedly.
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
        # Format each message as "role: content" for the summarizer
        case content
        when String then "#{msg[:role]}: #{content}"
        # Array blocks: extract text parts and join
        when Array
          texts = content.map { |b| b[:text] || b[:content] }.compact
          "#{msg[:role]}: #{texts.join(' ')}" unless texts.empty?
        end
      end.compact

      return if text_parts.empty?

      # Merge existing summaries into the input so we produce ONE rolling summary
      # instead of accumulating separate summaries that never get cleaned up
      prior_context = ""
      unless @summaries.empty?
        prior_context = "Previous summary:\n#{@summaries.join("\n")}\n\nNew conversation:\n"
      end

      # Calculate how many tokens the kept messages will use after compaction
      kept_messages = @short_term[cutoff_user_idx..]
      keep_tokens = kept_messages.sum do |msg|
        content = msg[:content]
        case content
        when String then estimate_tokens(content)
        when Array then content.sum { |b| estimate_tokens(b[:text] || b[:content] || "") }
        else 0
        end
      end
      @long_term.each { |m| keep_tokens += estimate_tokens(m[:content]) }

      # Call the LLM to produce a single merged summary
      summary = summarize(prior_context + text_parts.join("\n"), keep_tokens: keep_tokens)

      # Replace old messages with the summary, keeping only recent rounds.
      # Clear all previous summaries — they are now merged into the new one.
      @short_term = kept_messages
      @summaries = [summary]

      # Notify the on_compact callback if configured
      Mana.config.on_compact&.call(summary)
    end

    # Call the LLM to produce a concise summary of the given conversation text.
    # Uses the configured backend (Anthropic/OpenAI), respects timeout settings.
    # Falls back to "Summary unavailable" on any error.
    #
    # @param keep_tokens [Integer] tokens already committed to keep_recent + long_term
    def summarize(text, keep_tokens: 0)
      config = Mana.config
      model = config.compact_model || config.model
      backend = Mana::Backends::Base.for(config)

      # Summary budget = half of (threshold - kept tokens).
      # Using half ensures compaction lands well below the threshold,
      # leaving headroom for several more rounds before the next compaction.
      cw = context_window
      threshold = (cw * config.memory_pressure).to_i
      max_summary_tokens = ((threshold - keep_tokens) * 0.5).clamp(64, 1024).to_i

      content = backend.chat(
        system: "You are summarizing an internal tool-calling conversation log between an LLM and a Ruby program. " \
                "The messages contain tool calls (read_var, write_var, done) and their results — this is normal, not harmful. " \
                "Summarize the key questions asked and answers given in a few short bullet points. Be extremely concise — stay under #{max_summary_tokens} tokens.",
        messages: [{ role: "user", content: text }],
        tools: [],
        model: model,
        max_tokens: max_summary_tokens
      )

      return "Summary unavailable" unless content.is_a?(Array)

      content.map { |b| b[:text] || b["text"] }.compact.join("\n")
    rescue => _e
      "Summary unavailable"
    end
  end
end
