# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Session do
  describe ".current" do
    it "returns nil outside a session" do
      expect(described_class.current).to be_nil
    end

    it "returns the session inside a session block" do
      described_class.run do |session|
        expect(described_class.current).to eq(session)
        expect(described_class.current).to be_a(described_class)
      end
    end

    it "restores nil after session ends" do
      described_class.run { |_| }
      expect(described_class.current).to be_nil
    end

    it "restores previous session on nesting" do
      described_class.run do |outer|
        described_class.run do |inner|
          expect(described_class.current).to eq(inner)
        end
        expect(described_class.current).to eq(outer)
      end
    end
  end

  describe "#messages" do
    it "starts with empty messages" do
      described_class.run do |session|
        expect(session.messages).to eq([])
      end
    end

    it "accumulates messages across engine calls" do
      Mana.config.api_key = "test-key"

      # First call: LLM writes a var
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(
          { status: 200, headers: { "Content-Type" => "application/json" },
            body: JSON.generate({ content: [
              { type: "tool_use", id: "t1", name: "done", input: { "result" => "noted" } }
            ] }) },
          { status: 200, headers: { "Content-Type" => "application/json" },
            body: JSON.generate({ content: [
              { type: "tool_use", id: "t2", name: "done", input: { "result" => "translated" } }
            ] }) }
        )

      described_class.run do |session|
        b = binding
        Mana::Engine.run("remember: be concise", b)

        # After first call, messages should have user + assistant
        expect(session.messages.length).to be >= 2

        Mana::Engine.run("translate something", b)

        # After second call, messages should have accumulated
        expect(session.messages.length).to be >= 4
      end
    end
  end

  describe "Mana.session" do
    it "delegates to Session.run" do
      called = false
      Mana.session do |_session|
        called = true
        expect(Mana::Session.current).not_to be_nil
      end
      expect(called).to be true
    end
  end
end
