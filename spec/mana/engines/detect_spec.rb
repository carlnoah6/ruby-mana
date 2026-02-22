# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Engines do
  describe ".detect" do
    it "returns LLM for any input (stub)" do
      expect(described_class.detect("any natural language")).to eq(Mana::Engines::LLM)
    end

    it "returns LLM with context parameter" do
      expect(described_class.detect("code", context: :repl)).to eq(Mana::Engines::LLM)
    end
  end
end
