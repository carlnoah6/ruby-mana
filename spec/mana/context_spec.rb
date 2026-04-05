# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Context do
  before do
    Thread.current[:mana_context] = nil
    Thread.current[:mana_memory] = nil
    Mana.config.api_key = "test-key"
  end

  after do
    Thread.current[:mana_context] = nil
    Thread.current[:mana_memory] = nil
    Mana.reset!
  end

  describe ".current" do
    it "auto-creates context for the current thread" do
      context = described_class.current
      expect(context).to be_a(described_class)
    end

    it "returns the same context on subsequent calls" do
      c1 = described_class.current
      c2 = described_class.current
      expect(c1).to equal(c2)
    end
  end

  describe "default context (consecutive calls share context)" do
    it "shares messages across engine calls" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "done", input: { "result" => "noted" } }],
        [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "translated" } }]
      )

      b = binding
      Mana::Engine.run("remember: be concise", b)
      context = Mana.memory
      expect(context.messages.length).to be >= 2

      Mana::Engine.run("translate something", b)
      expect(context.messages.length).to be >= 4
    end
  end

  describe "#messages" do
    it "starts empty" do
      context = described_class.new
      expect(context.messages).to eq([])
    end
  end

  describe "#summaries" do
    it "starts empty" do
      context = described_class.new
      expect(context.summaries).to eq([])
    end
  end

  describe "#clear!" do
    it "clears messages and summaries" do
      context = described_class.new
      context.messages << { role: "user", content: "test" }
      context.summaries << "a summary"

      context.clear!
      expect(context.messages).to be_empty
      expect(context.summaries).to be_empty
    end
  end

  describe "#clear_messages!" do
    it "clears messages and summaries" do
      context = described_class.new
      context.messages << { role: "user", content: "test" }
      context.summaries << "a summary"

      context.clear_messages!
      expect(context.messages).to be_empty
      expect(context.summaries).to be_empty
    end
  end

  describe "#token_count" do
    it "estimates tokens from messages" do
      context = described_class.new
      context.messages << { role: "user", content: "hello world" }
      expect(context.token_count).to be > 0
    end

    it "returns 0 for empty context" do
      context = described_class.new
      expect(context.token_count).to eq(0)
    end

    it "includes summaries in count" do
      context = described_class.new
      context.summaries << "This is a summary of a previous conversation"
      expect(context.token_count).to be > 0
    end
  end

  describe "#inspect" do
    it "returns human-readable representation" do
      context = described_class.new
      result = context.inspect
      expect(result).to match(/Mana::Context/)
      expect(result).to match(/messages=/)
      expect(result).to match(/tokens=/)
    end
  end

  describe "Mana.memory" do
    it "returns current thread context" do
      context = Mana.memory
      expect(context).to be_a(described_class)
      expect(context).to equal(described_class.current)
    end
  end
end
