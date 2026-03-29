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

    # Rough token estimate: ~4 characters per token
    def estimate_tokens(text)
      return 0 unless text.is_a?(String)

      (text.length / 4.0).ceil
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
  end
end
