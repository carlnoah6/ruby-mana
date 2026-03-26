# frozen_string_literal: true

require "spec_helper"

RSpec.describe "String#~@" do
  before { Mana.config.api_key = "test-key" }

  it "is defined on String" do
    expect("hello").to respond_to(:~@)
  end

  it "calls Mana::Engine.run" do
    expect(Mana::Engine).to receive(:run).with("test prompt", anything)

    stub_anthropic_text_only
    ~"test prompt"
  end

  it "passes caller binding so write_var sets local variables" do
    stub_anthropic_sequence(
      [{ type: "tool_use", id: "t1", name: "write_var", input: { "name" => "answer", "value" => 42 } }],
      [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "ok" } }]
    )

    answer = nil
    ~"compute and store in <answer>"
    expect(answer).to eq(42)
  end

  it "returns the written value" do
    stub_anthropic_sequence(
      [{ type: "tool_use", id: "t1", name: "write_var", input: { "name" => "x", "value" => 99 } }],
      [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "ok" } }]
    )

    result = ~"compute and store in <x>"
    expect(result).to eq(99)
  end
end
