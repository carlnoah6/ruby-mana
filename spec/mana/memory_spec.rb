# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Memory do
  before do
    Thread.current[:mana_memory] = nil
    # Use a temp directory for file store
    @tmpdir = Dir.mktmpdir("mana_test")
    Mana.config.memory_store = Mana::FileStore.new(@tmpdir)
    Mana.config.api_key = "test-key"
  end

  after do
    Thread.current[:mana_memory] = nil
    FileUtils.rm_rf(@tmpdir)
    Mana.reset!
  end

  describe ".current" do
    it "auto-creates memory for the current thread" do
      memory = described_class.current
      expect(memory).to be_a(described_class)
    end

    it "returns the same memory on subsequent calls" do
      m1 = described_class.current
      m2 = described_class.current
      expect(m1).to equal(m2)
    end

    it "returns nil in incognito mode" do
      described_class.incognito do
        expect(described_class.current).to be_nil
      end
    end
  end

  describe "default memory (consecutive calls share context)" do
    it "shares messages across engine calls" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "done", input: { "result" => "noted" } }],
        [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "translated" } }]
      )

      b = binding
      Mana::Engine.run("remember: be concise", b)
      context = Mana.memory  # returns Mana::Context
      expect(context.messages.length).to be >= 2

      Mana::Engine.run("translate something", b)
      expect(context.messages.length).to be >= 4
    end
  end

  describe ".incognito?" do
    it "returns false normally" do
      expect(described_class.incognito?).to be false
    end

    it "returns true inside incognito block" do
      described_class.incognito do
        expect(described_class.incognito?).to be true
      end
    end

    it "restores state after incognito block" do
      described_class.incognito { }
      expect(described_class.incognito?).to be false
    end
  end

  describe ".incognito" do
    it "isolates memory completely" do
      outer_memory = described_class.current
      outer_memory.short_term << { role: "user", content: "test" }

      described_class.incognito do
        expect(described_class.current).to be_nil
      end

      expect(described_class.current).to equal(outer_memory)
      expect(outer_memory.short_term.size).to eq(1)
    end

    it "blocks remember tool in incognito mode" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "remember", input: { "content" => "secret" } }],
        [{ type: "tool_use", id: "t2", name: "done", input: {} }]
      )

      described_class.incognito do
        b = binding
        Mana::Engine.run("remember this secret", b)
      end

      # No long-term memories should exist
      memory = described_class.current
      expect(memory.long_term).to be_empty
    end
  end

  describe "#short_term" do
    it "starts empty" do
      memory = described_class.new
      expect(memory.short_term).to eq([])
    end
  end

  describe "#long_term" do
    it "starts empty when no persisted data" do
      memory = described_class.new
      expect(memory.long_term).to eq([])
    end

    it "loads persisted data on initialization" do
      store = Mana.config.memory_store
      store.write(File.basename(`git rev-parse --show-toplevel 2>/dev/null`.strip), [
        { id: 1, content: "test fact", created_at: "2026-01-01T00:00:00+00:00" }
      ])

      memory = described_class.new
      expect(memory.long_term.size).to eq(1)
      expect(memory.long_term.first[:content]).to eq("test fact")
    end
  end

  describe "#remember" do
    it "adds to long_term with auto-increment ID" do
      memory = described_class.new
      entry1 = memory.remember("fact one")
      entry2 = memory.remember("fact two")

      expect(entry1[:id]).to eq(1)
      expect(entry2[:id]).to eq(2)
      expect(memory.long_term.size).to eq(2)
    end

    it "deduplicates identical content" do
      memory = described_class.new
      entry1 = memory.remember("same fact")
      entry2 = memory.remember("same fact")
      entry3 = memory.remember("different fact")

      expect(entry1).to equal(entry2)  # returns same object
      expect(memory.long_term.size).to eq(2)
      expect(entry3[:id]).to eq(2)
    end

    it "persists to disk immediately" do
      memory = described_class.new
      memory.remember("persisted fact")

      store = Mana.config.memory_store
      data = store.read(File.basename(`git rev-parse --show-toplevel 2>/dev/null`.strip))
      expect(data.size).to eq(1)
      expect(data.first[:content]).to eq("persisted fact")
    end

    it "includes timestamp" do
      memory = described_class.new
      entry = memory.remember("timestamped")
      expect(entry[:created_at]).not_to be_nil
    end
  end

  describe "#forget" do
    it "removes a specific long-term memory by ID" do
      memory = described_class.new
      memory.remember("keep this")
      memory.remember("forget this")
      memory.remember("keep this too")

      memory.forget(id: 2)
      expect(memory.long_term.size).to eq(2)
      expect(memory.long_term.map { |m| m[:content] }).to eq(["keep this", "keep this too"])
    end

    it "persists the change to disk" do
      memory = described_class.new
      memory.remember("to forget")
      memory.forget(id: 1)

      store = Mana.config.memory_store
      data = store.read(File.basename(`git rev-parse --show-toplevel 2>/dev/null`.strip))
      expect(data).to be_empty
    end

    it "does not raise with nonexistent id" do
      memory = described_class.new
      memory.remember("a fact")
      expect { memory.forget(id: 999) }.not_to raise_error
      expect(memory.long_term.size).to eq(1)
    end
  end

  describe "#clear!" do
    it "clears both short-term and long-term" do
      memory = described_class.new
      memory.short_term << { role: "user", content: "test" }
      memory.remember("fact")

      memory.clear!
      expect(memory.short_term).to be_empty
      expect(memory.long_term).to be_empty
    end
  end

  describe "#clear_short_term!" do
    it "clears only short-term messages and summaries" do
      memory = described_class.new
      memory.short_term << { role: "user", content: "test" }
      memory.remember("fact")

      memory.clear_short_term!
      expect(memory.short_term).to be_empty
      expect(memory.long_term.size).to eq(1)
    end
  end

  describe "#clear_long_term!" do
    it "clears only long-term memories and persists" do
      memory = described_class.new
      memory.short_term << { role: "user", content: "test" }
      memory.remember("fact")

      memory.clear_long_term!
      expect(memory.long_term).to be_empty
      expect(memory.short_term.size).to eq(1)

      store = Mana.config.memory_store
      data = store.read(File.basename(`git rev-parse --show-toplevel 2>/dev/null`.strip))
      expect(data).to be_empty
    end
  end

  describe "#token_count" do
    it "estimates tokens from short-term messages" do
      memory = described_class.new
      memory.short_term << { role: "user", content: "hello world" }
      expect(memory.token_count).to be > 0
    end

    it "includes long-term memories in count" do
      memory = described_class.new
      memory.remember("a fact to remember")
      expect(memory.token_count).to be > 0
    end

    it "returns 0 for empty memory" do
      memory = described_class.new
      expect(memory.token_count).to eq(0)
    end

    it "includes summaries in count" do
      memory = described_class.new
      memory.summaries << "This is a summary of a previous conversation"
      count_with_summary = memory.token_count
      expect(count_with_summary).to be > 0
    end
  end

  describe "#inspect" do
    it "returns human-readable representation" do
      memory = described_class.new
      memory.remember("a fact")
      result = memory.inspect
      expect(result).to match(/Mana::Memory/)
      expect(result).to match(/long_term=1/)
      expect(result).to match(/tokens=/)
    end
  end

  describe "Mana.memory" do
    it "returns current thread context (Mana::Context)" do
      # Mana.memory now returns Mana::Context, not Mana::Memory
      ctx = Mana.memory
      expect(ctx).to be_a(Mana::Context)
    end
  end

  # incognito removed from mana — now handled by claw

  # remember tool integration tests moved to claw specs
  # (remember is now a registered tool from claw, not built into mana)
end
