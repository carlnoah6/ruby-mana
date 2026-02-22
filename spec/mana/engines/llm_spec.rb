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
    it "runs the tool-calling loop and returns done result" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "write_var", input: { "name" => "x", "value" => 42 } }],
        [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "ok" } }]
      )

      b = binding
      engine = described_class.new(b)
      result = engine.execute("set <x> to 42")
      expect(result).to eq("ok")
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
