# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Engine do
  before { Mana.config.api_key = "test-key" }

  describe ".run" do
    it "handles write_var to create new variables" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "write_var", input: { "name" => "result", "value" => 3.0 } }],
        [{ type: "tool_use", id: "t2", name: "done", input: {} }]
      )

      b = binding
      Mana::Engine.run("compute average and store in <result>", b)
      expect(b.local_variable_get(:result)).to eq(3.0)
    end

    it "handles read_var for existing variables" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "read_var", input: { "name" => "numbers" } }],
        [{ type: "tool_use", id: "t2", name: "write_var", input: { "name" => "total", "value" => 6 } }],
        [{ type: "tool_use", id: "t3", name: "done", input: {} }]
      )

      numbers = [1, 2, 3] # rubocop:disable Lint/UselessAssignment
      b = binding
      Mana::Engine.run("sum <numbers> into <total>", b)
      expect(b.local_variable_get(:total)).to eq(6)
    end

    it "handles read_attr and write_attr on objects" do
      klass = Struct.new(:name, :category, keyword_init: true)
      obj = klass.new(name: "test", category: nil)

      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "read_attr", input: { "obj" => "item", "attr" => "name" } }],
        [{ type: "tool_use", id: "t2", name: "write_attr", input: { "obj" => "item", "attr" => "category", "value" => "urgent" } }],
        [{ type: "tool_use", id: "t3", name: "done", input: {} }]
      )

      item = obj # rubocop:disable Lint/UselessAssignment
      b = binding
      Mana::Engine.run("read <item> name and set category", b)
      expect(obj.category).to eq("urgent")
    end

    it "handles call_func" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "double", "args" => [21] } }],
        [{ type: "tool_use", id: "t2", name: "write_var", input: { "name" => "result", "value" => 42 } }],
        [{ type: "tool_use", id: "t3", name: "done", input: {} }]
      )

      def double(n) = n * 2 # rubocop:disable Lint/UselessMethodDefinition

      b = binding
      Mana::Engine.run("call double(21) and store in <result>", b)
      expect(b.local_variable_get(:result)).to eq(42)
    end

    it "stops when LLM returns no tool calls" do
      stub_anthropic_text_only("All done!")

      b = binding
      expect { Mana::Engine.run("just say hi", b) }.not_to raise_error
    end

    it "raises on max iterations exceeded" do
      # Always return a tool call, never done
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            content: [{ type: "tool_use", id: "t1", name: "read_var", input: { "name" => "x" } }]
          })
        )

      orig = Mana.config.max_iterations
      begin
        Mana.config.max_iterations = 3
        x = 1 # rubocop:disable Lint/UselessAssignment
        b = binding
        expect { Mana::Engine.run("loop forever on <x>", b) }.to raise_error(Mana::MaxIterationsError)
      ensure
        Mana.config.max_iterations = orig
      end
    end

    it "raises on HTTP error" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 500, body: "Internal Server Error")

      b = binding
      expect { Mana::Engine.run("fail", b) }.to raise_error(Mana::LLMError, /HTTP 500/)
    end

    it "returns done result" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "done", input: { "result" => "finished" } }]
      )

      b = binding
      result = Mana::Engine.run("do something", b)
      expect(result).to eq("finished")
    end

    it "rejects invalid variable names in write_var" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "write_var", input: { "name" => "system('rm -rf /')", "value" => 1 } }],
        [{ type: "tool_use", id: "t2", name: "done", input: {} }]
      )

      b = binding
      # Should not raise — error is caught and returned to LLM
      expect { Mana::Engine.run("try injection", b) }.not_to raise_error
    end

    it "rejects invalid function names in call_func" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "eval('bad')", "args" => [] } }],
        [{ type: "tool_use", id: "t2", name: "done", input: {} }]
      )

      b = binding
      expect { Mana::Engine.run("try injection", b) }.not_to raise_error
    end

    it "rejects invalid attr names in read_attr" do
      klass = Struct.new(:name, keyword_init: true)
      obj = klass.new(name: "test")

      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "read_attr", input: { "obj" => "item", "attr" => "send('exit')" } }],
        [{ type: "tool_use", id: "t2", name: "done", input: {} }]
      )

      item = obj # rubocop:disable Lint/UselessAssignment
      b = binding
      expect { Mana::Engine.run("try injection", b) }.not_to raise_error
    end

    it "handles multiple tool calls in one response" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            content: [
              { type: "tool_use", id: "t1", name: "write_var", input: { "name" => "a", "value" => 1 } },
              { type: "tool_use", id: "t2", name: "write_var", input: { "name" => "b", "value" => 2 } }
            ]
          })
        ).then
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            content: [{ type: "tool_use", id: "t3", name: "done", input: {} }]
          })
        )

      b = binding
      Mana::Engine.run("set a=1 and b=2", b)
      expect(b.local_variable_get(:a)).to eq(1)
      expect(b.local_variable_get(:b)).to eq(2)
    end

    it "handles unknown tool gracefully" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "nonexistent_tool", input: {} }],
        [{ type: "tool_use", id: "t2", name: "done", input: {} }]
      )

      b = binding
      expect { Mana::Engine.run("test", b) }.not_to raise_error
    end
  end

  describe "#build_context" do
    it "reads existing variables referenced in prompt" do
      engine = Mana::Engine.new("use <x> and <y>", binding.tap { |b|
        b.local_variable_set(:x, 42)
        b.local_variable_set(:y, "hello")
      })

      ctx = engine.send(:build_context, "use <x> and <y>")
      expect(ctx["x"]).to eq("42")
      expect(ctx["y"]).to eq('"hello"')
    end

    it "skips variables that don't exist yet" do
      b = binding
      engine = Mana::Engine.new("store in <new_var>", b)
      ctx = engine.send(:build_context, "store in <new_var>")
      expect(ctx).to be_empty
    end
  end

  describe "#serialize_value" do
    let(:engine) { Mana::Engine.new("test", binding) }

    it "serializes primitives" do
      expect(engine.send(:serialize_value, 42)).to eq("42")
      expect(engine.send(:serialize_value, 3.14)).to eq("3.14")
      expect(engine.send(:serialize_value, "hello")).to eq('"hello"')
      expect(engine.send(:serialize_value, true)).to eq("true")
      expect(engine.send(:serialize_value, nil)).to eq("nil")
    end

    it "serializes arrays" do
      expect(engine.send(:serialize_value, [1, "two", 3])).to eq('[1, "two", 3]')
    end

    it "serializes hashes" do
      result = engine.send(:serialize_value, { a: 1 })
      expect(result).to include('"a" => 1')
    end

    it "serializes custom objects via instance variables" do
      klass = Struct.new(:name, :age, keyword_init: true)
      obj = klass.new(name: "Alice", age: 30)
      result = engine.send(:serialize_value, obj)
      expect(result).to include("name")
      expect(result).to include("Alice")
    end
  end
end
