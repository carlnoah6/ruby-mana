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

      Mana.config.max_iterations = 3
      x = 1 # rubocop:disable Lint/UselessAssignment
      b = binding
      expect { Mana::Engine.run("loop forever on <x>", b) }.to raise_error(Mana::MaxIterationsError)
      Mana.config.max_iterations = 50
    end

    it "raises on HTTP error" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 500, body: "Internal Server Error")

      b = binding
      expect { Mana::Engine.run("fail", b) }.to raise_error(Mana::LLMError, /HTTP 500/)
    end
  end
end
