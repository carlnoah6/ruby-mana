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
end
