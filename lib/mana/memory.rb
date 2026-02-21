# frozen_string_literal: true

module Mana
  class Memory
    attr_reader :short_term, :long_term, :summaries

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
      def current
        return nil if incognito?

        Thread.current[:mana_memory] ||= new
      end

      def incognito?
        Thread.current[:mana_incognito] == true
      end

      def incognito(&block)
        previous_memory = Thread.current[:mana_memory]
        previous_incognito = Thread.current[:mana_incognito]
        Thread.current[:mana_incognito] = true
        Thread.current[:mana_memory] = nil
        block.call
      ensure
        Thread.current[:mana_incognito] = previous_incognito
        Thread.current[:mana_memory] = previous_memory
      end
    end

    # --- Token estimation ---

    def token_count
      count = 0
      @short_term.each do |msg|
        content = msg[:content]
        case content
        when String
          count += estimate_tokens(content)
        when Array
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

    def clear!
      clear_short_term!
      clear_long_term!
    end

    def clear_short_term!
      @short_term.clear
      @summaries.clear
    end

    def clear_long_term!
      @long_term.clear
      store.clear(namespace)
    end

    def forget(id:)
      @long_term.reject! { |m| m[:id] == id }
      store.write(namespace, @long_term)
    end

    def remember(content)
      entry = { id: @next_id, content: content, created_at: Time.now.iso8601 }
      @next_id += 1
      @long_term << entry
      store.write(namespace, @long_term)
      entry
    end

    # --- Compaction ---

    def compact!
      wait_for_compaction
      perform_compaction
    end

    def needs_compaction?
      cw = context_window
      token_count > (cw * Mana.config.memory_pressure)
    end

    def schedule_compaction
      return unless needs_compaction?

      @compact_mutex.synchronize do
        return if @compact_thread&.alive?

        @compact_thread = Thread.new do
          perform_compaction
        rescue => e
          # Silently handle compaction errors — don't crash the main thread
          $stderr.puts "Mana compaction error: #{e.message}" if $DEBUG
        end
      end
    end

    def wait_for_compaction
      thread = @compact_mutex.synchronize { @compact_thread }
      thread&.join
    end

    # --- Display ---

    def inspect
      "#<Mana::Memory long_term=#{@long_term.size}, short_term=#{short_term_rounds} rounds, tokens=#{token_count}/#{context_window}>"
    end

    private

    def short_term_rounds
      @short_term.count { |m| m[:role] == "user" && m[:content].is_a?(String) }
    end

    def estimate_tokens(text)
      return 0 unless text.is_a?(String)

      # Rough estimate: ~4 chars per token
      (text.length / 4.0).ceil
    end

    def context_window
      Mana.config.context_window || ContextWindow.detect(Mana.config.model)
    end

    def store
      Mana.config.memory_store || default_store
    end

    def default_store
      @default_store ||= FileStore.new
    end

    def namespace
      Namespace.detect
    end

    def load_long_term
      return if self.class.incognito?

      @long_term = store.read(namespace)
      @next_id = (@long_term.map { |m| m[:id] }.max || 0) + 1
    end

    def perform_compaction
      keep_recent = Mana.config.memory_keep_recent
      # Count user-prompt messages (rounds)
      user_indices = @short_term.each_with_index
        .select { |msg, _| msg[:role] == "user" && msg[:content].is_a?(String) }
        .map(&:last)

      return if user_indices.size <= keep_recent

      # Find the cutoff point: keep the last N rounds
      cutoff_user_idx = user_indices[-(keep_recent)]
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

      summary = summarize(text_parts.join("\n"))

      # Replace old messages with summary
      @short_term = @short_term[cutoff_user_idx..]
      @summaries << summary

      Mana.config.on_compact&.call(summary)
    end

    def summarize(text)
      config = Mana.config
      model = config.compact_model || config.model
      uri = URI("#{config.base_url}/v1/messages")

      body = {
        model: model,
        max_tokens: 1024,
        system: "Summarize this conversation concisely. Preserve key facts, decisions, and context.",
        messages: [{ role: "user", content: text }]
      }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 60

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req["x-api-key"] = config.api_key
      req["anthropic-version"] = "2023-06-01"
      req.body = JSON.generate(body)

      res = http.request(req)
      return "Summary unavailable" unless res.is_a?(Net::HTTPSuccess)

      parsed = JSON.parse(res.body, symbolize_names: true)
      content = parsed[:content]
      return "Summary unavailable" unless content.is_a?(Array)

      content.map { |b| b[:text] }.compact.join("\n")
    rescue => _e
      "Summary unavailable"
    end
  end
end
