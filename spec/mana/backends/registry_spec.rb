# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Backends::Base do
  describe ".for" do
    # Helper to create a config with a dummy API key for routing tests
    def config_with(model:, backend: nil)
      config = Mana::Config.new
      config.api_key = "test-key"
      config.model = model
      config.backend = backend if backend
      config
    end

    it "raises ConfigError when API key is missing" do
      config = Mana::Config.new
      config.api_key = nil
      expect { described_class.for(config) }.to raise_error(Mana::ConfigError, /API key is not configured/)
    end

    it "raises ConfigError when API key is whitespace-only" do
      config = Mana::Config.new
      config.api_key = "   "
      expect { described_class.for(config) }.to raise_error(Mana::ConfigError, /API key is not configured/)
    end

    it "returns Anthropic backend for claude-* models" do
      config = config_with(model: "claude-sonnet-4-20250514")
      config.model = "claude-sonnet-4-20250514"
      expect(described_class.for(config)).to be_a(Mana::Backends::Anthropic)
    end

    it "returns Anthropic backend for claude-3 models" do
      expect(described_class.for(config_with(model: "claude-3-haiku-20240307"))).to be_a(Mana::Backends::Anthropic)
    end

    it "returns OpenAI backend for gpt-* models" do
      expect(described_class.for(config_with(model: "gpt-4o"))).to be_a(Mana::Backends::OpenAI)
    end

    it "returns OpenAI backend for o1-* models" do
      expect(described_class.for(config_with(model: "o1-preview"))).to be_a(Mana::Backends::OpenAI)
    end

    it "returns OpenAI backend for o3-* models" do
      expect(described_class.for(config_with(model: "o3-mini"))).to be_a(Mana::Backends::OpenAI)
    end

    it "defaults to OpenAI for unknown models" do
      expect(described_class.for(config_with(model: "llama3"))).to be_a(Mana::Backends::OpenAI)
    end

    it "defaults to OpenAI for deepseek models" do
      expect(described_class.for(config_with(model: "deepseek-chat"))).to be_a(Mana::Backends::OpenAI)
    end

    it "respects explicit :anthropic backend setting" do
      expect(described_class.for(config_with(model: "gpt-4o", backend: :anthropic))).to be_a(Mana::Backends::Anthropic)
    end

    it "respects explicit :openai backend setting" do
      expect(described_class.for(config_with(model: "claude-sonnet-4-20250514", backend: :openai))).to be_a(Mana::Backends::OpenAI)
    end

    it "respects explicit string 'openai' backend setting" do
      expect(described_class.for(config_with(model: "llama-3.3-70b-versatile", backend: "openai"))).to be_a(Mana::Backends::OpenAI)
    end

    it "returns a Backend instance directly if provided" do
      config = config_with(model: "claude-sonnet-4-20250514")
      custom_backend = Mana::Backends::Anthropic.new(config)
      config.backend = custom_backend
      expect(described_class.for(config)).to equal(custom_backend)
    end
  end
end
