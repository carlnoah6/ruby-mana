# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Backends do
  describe ".for" do
    it "returns Anthropic backend for claude-* models" do
      config = Mana::Config.new
      config.model = "claude-sonnet-4-20250514"
      expect(described_class.for(config)).to be_a(Mana::Backends::Anthropic)
    end

    it "returns Anthropic backend for claude-3 models" do
      config = Mana::Config.new
      config.model = "claude-3-haiku-20240307"
      expect(described_class.for(config)).to be_a(Mana::Backends::Anthropic)
    end

    it "returns OpenAI backend for gpt-* models" do
      config = Mana::Config.new
      config.model = "gpt-4o"
      expect(described_class.for(config)).to be_a(Mana::Backends::OpenAI)
    end

    it "returns OpenAI backend for o1-* models" do
      config = Mana::Config.new
      config.model = "o1-preview"
      expect(described_class.for(config)).to be_a(Mana::Backends::OpenAI)
    end

    it "returns OpenAI backend for o3-* models" do
      config = Mana::Config.new
      config.model = "o3-mini"
      expect(described_class.for(config)).to be_a(Mana::Backends::OpenAI)
    end

    it "defaults to OpenAI for unknown models" do
      config = Mana::Config.new
      config.model = "llama3"
      expect(described_class.for(config)).to be_a(Mana::Backends::OpenAI)
    end

    it "defaults to OpenAI for deepseek models" do
      config = Mana::Config.new
      config.model = "deepseek-chat"
      expect(described_class.for(config)).to be_a(Mana::Backends::OpenAI)
    end

    it "respects explicit :anthropic backend setting" do
      config = Mana::Config.new
      config.backend = :anthropic
      config.model = "gpt-4o" # would normally auto-detect as OpenAI
      expect(described_class.for(config)).to be_a(Mana::Backends::Anthropic)
    end

    it "respects explicit :openai backend setting" do
      config = Mana::Config.new
      config.backend = :openai
      config.model = "claude-sonnet-4-20250514" # would normally auto-detect as Anthropic
      expect(described_class.for(config)).to be_a(Mana::Backends::OpenAI)
    end

    it "respects explicit string 'openai' backend setting" do
      config = Mana::Config.new
      config.backend = "openai"
      config.model = "llama-3.3-70b-versatile"
      expect(described_class.for(config)).to be_a(Mana::Backends::OpenAI)
    end

    it "returns a Backend instance directly if provided" do
      config = Mana::Config.new
      custom_backend = Mana::Backends::Anthropic.new(config)
      config.backend = custom_backend
      expect(described_class.for(config)).to equal(custom_backend)
    end
  end
end
