# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Engines::LLM do
  before do
    Mana.config.api_key = "test-key"
    Thread.current[:mana_memory] = nil
    Thread.current[:mana_incognito] = nil
    @tmpdir = Dir.mktmpdir("mana_test")
    Mana.config.memory_store = Mana::FileStore.new(@tmpdir)
  end

  after do
    Thread.current[:mana_memory] = nil
    Thread.current[:mana_incognito] = nil
    FileUtils.rm_rf(@tmpdir)
    Mana.reset!
  end

  describe "#execute" do
    it "runs the tool-calling loop and returns written variable value" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "write_var", input: { "name" => "x", "value" => 42 } }],
        [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "ok" } }]
      )

      b = binding
      engine = described_class.new(b)
      result = engine.execute("set <x> to 42")
      expect(result).to eq(42)  # returns written value for Ruby 4.0+ compatibility
      expect(b.local_variable_get(:x)).to eq(42)
    end
  end

  describe ".all_tools" do
    it "includes built-in tools and remember" do
      names = described_class.all_tools.map { |t| t[:name] }
      expect(names).to include("read_var", "write_var", "call_func", "done", "remember")
    end

    it "excludes remember in incognito mode" do
      Mana::Memory.incognito do
        names = described_class.all_tools.map { |t| t[:name] }
        expect(names).not_to include("remember")
      end
    end
  end

  describe ".handler_stack" do
    it "returns a thread-local array" do
      expect(described_class.handler_stack).to be_an(Array)
    end
  end

  describe ".with_handler" do
    it "pushes and pops handler from the stack" do
      handler = ->(_name, _input) { "handled" }
      described_class.with_handler(handler) do
        expect(described_class.handler_stack.last).to eq(handler)
      end
      expect(described_class.handler_stack).to be_empty
    end
  end

  describe "call_func with dotted methods" do
    it "allows Class.method calls like Time.now" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "Time.now" } }],
        [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "ok" } }]
      )

      b = binding
      engine = described_class.new(b)
      result = engine.execute("get time")
      expect(result).to eq("ok")
    end

    it "allows chained calls like Time.now.to_s" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "Time.now.to_s" } }],
        [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "ok" } }]
      )

      b = binding
      engine = described_class.new(b)
      result = engine.execute("get time string")
      expect(result).to eq("ok")
    end

    it "blocks receiver calls per security policy" do
      Mana.config.security = :strict
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "File.read", "args" => ["/etc/hosts"] } }],
        [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "ok" } }]
      )

      b = binding
      engine = described_class.new(b)
      # Should not raise — error is caught and returned as tool result
      engine.execute("read file")
    end

    it "blocks methods per security policy" do
      Mana.config.security = :strict
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "eval" } }],
        [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "ok" } }]
      )

      b = binding
      engine = described_class.new(b)
      engine.execute("eval something")
    end
  end

  describe "serialize_value" do
    it "serializes Time objects as readable strings" do
      b = binding
      engine = described_class.new(b)
      result = engine.send(:serialize_value, Time.new(2026, 3, 23, 12, 0, 0, "+08:00"))
      expect(result).to include("2026-03-23")
      expect(result).to include("12:00:00")
    end
  end

  describe "verbose mode" do
    it "logs to stderr when verbose is true" do
      Mana.config.verbose = true
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "done", input: { "result" => "ok" } }]
      )

      b = binding
      engine = described_class.new(b)
      expect { engine.execute("test") }.to output(/LLM call/).to_stderr
      Mana.config.verbose = false
    end

    it "does not log when verbose is false" do
      Mana.config.verbose = false
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "done", input: { "result" => "ok" } }]
      )

      b = binding
      engine = described_class.new(b)
      expect { engine.execute("test") }.not_to output.to_stderr
    end
  end

  describe "#handle_mock" do
    it "matches and returns stubbed values" do
      Mana.mock!
      Mana.current_mock.prompt("test", value: 42)

      b = binding
      engine = described_class.new(b)
      result = engine.handle_mock("test prompt")
      expect(b.local_variable_get(:value)).to eq(42)

      Mana.unmock!
    end
  end
end
