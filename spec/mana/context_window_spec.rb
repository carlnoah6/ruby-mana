# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::ContextWindow do
  describe ".detect" do
    it "returns 200_000 for Claude Sonnet 4" do
      expect(described_class.detect("claude-sonnet-4-20250514")).to eq(200_000)
    end

    it "returns 200_000 for Claude 3.5 Sonnet" do
      expect(described_class.detect("claude-3-5-sonnet-20241022")).to eq(200_000)
    end

    it "returns 200_000 for Claude 3.5 Haiku" do
      expect(described_class.detect("claude-3-5-haiku-20241022")).to eq(200_000)
    end

    it "returns 200_000 for Claude 3 Opus" do
      expect(described_class.detect("claude-3-opus-20240229")).to eq(200_000)
    end

    it "returns 128_000 for GPT-4o" do
      expect(described_class.detect("gpt-4o")).to eq(128_000)
    end

    it "returns 128_000 for GPT-4 Turbo" do
      expect(described_class.detect("gpt-4-turbo")).to eq(128_000)
    end

    it "returns 16_385 for GPT-3.5" do
      expect(described_class.detect("gpt-3.5-turbo")).to eq(16_385)
    end

    it "returns default for unknown model" do
      expect(described_class.detect("unknown-model")).to eq(128_000)
    end

    it "returns default for nil model" do
      expect(described_class.detect(nil)).to eq(128_000)
    end
  end
end
