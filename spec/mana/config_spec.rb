# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Config do
  subject(:config) { described_class.new }

  describe "defaults" do
    it "sets model to claude-sonnet-4" do
      expect(config.model).to eq("claude-sonnet-4-6")
    end

    it "sets temperature to 0" do
      expect(config.temperature).to eq(0)
    end

    it "reads api_key from ANTHROPIC_API_KEY first" do
      expect(config.api_key).to eq(ENV["ANTHROPIC_API_KEY"] || ENV["OPENAI_API_KEY"])
    end

    it "sets max_iterations to 50" do
      expect(config.max_iterations).to eq(50)
    end

    it "sets timeout to 120" do
      expect(config.timeout).to eq(120)
    end

    it "defaults base_url to nil (resolved dynamically)" do
      expect(config.base_url).to be_nil unless ENV["ANTHROPIC_API_URL"] || ENV["OPENAI_API_URL"]
    end

    it "sets memory_pressure to 0.7" do
      expect(config.memory_pressure).to eq(0.7)
    end

    it "sets memory_keep_recent to 4" do
      expect(config.memory_keep_recent).to eq(4)
    end

    it "defaults namespace to nil" do
      expect(config.namespace).to be_nil
    end

    it "defaults compact_model to nil" do
      expect(config.compact_model).to be_nil
    end
  end

  describe "effective_base_url" do
    it "returns Anthropic URL for claude models" do
      config.model = "claude-sonnet-4-20250514"
      config.base_url = nil
      expect(config.effective_base_url).to eq("https://api.anthropic.com")
    end

    it "returns OpenAI URL for gpt models" do
      config.model = "gpt-4o"
      config.base_url = nil
      expect(config.effective_base_url).to eq("https://api.openai.com")
    end

    it "returns explicit base_url when set" do
      config.base_url = "http://localhost:11434"
      expect(config.effective_base_url).to eq("http://localhost:11434")
    end

    it "respects explicit backend override for Anthropic" do
      config.backend = :anthropic
      config.model = "custom-model"
      config.base_url = nil
      expect(config.effective_base_url).to eq("https://api.anthropic.com")
    end

    it "respects explicit backend override for OpenAI" do
      config.backend = :openai
      config.model = "claude-sonnet-4-20250514"
      config.base_url = nil
      expect(config.effective_base_url).to eq("https://api.openai.com")
    end
  end

  describe "timeout validation" do
    it "accepts a positive integer" do
      config.timeout = 60
      expect(config.timeout).to eq(60)
    end

    it "accepts a positive float" do
      config.timeout = 30.5
      expect(config.timeout).to eq(30.5)
    end

    it "rejects nil" do
      expect { config.timeout = nil }.to raise_error(ArgumentError, /positive number/)
    end

    it "rejects zero" do
      expect { config.timeout = 0 }.to raise_error(ArgumentError, /positive number/)
    end

    it "rejects negative numbers" do
      expect { config.timeout = -5 }.to raise_error(ArgumentError, /positive number/)
    end

    it "rejects non-numeric values" do
      expect { config.timeout = "fast" }.to raise_error(ArgumentError, /positive number/)
    end
  end

  describe "environment variable overrides" do
    around do |example|
      saved = %w[MANA_VERBOSE MANA_BACKEND MANA_MODEL MANA_TIMEOUT MANA_SECURITY].map { |k| [k, ENV[k]] }
      example.run
    ensure
      saved.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
    end

    it "MANA_VERBOSE sets verbose to true" do
      ENV["MANA_VERBOSE"] = "true"
      c = described_class.new
      expect(c.verbose).to be true
    end

    it "MANA_BACKEND sets backend to symbol" do
      ENV["MANA_BACKEND"] = "openai"
      c = described_class.new
      expect(c.backend).to eq(:openai)
    end

    it "MANA_MODEL overrides default model" do
      ENV["MANA_MODEL"] = "gpt-4o"
      c = described_class.new
      expect(c.model).to eq("gpt-4o")
    end

    it "MANA_TIMEOUT overrides default timeout" do
      ENV["MANA_TIMEOUT"] = "30"
      c = described_class.new
      expect(c.timeout).to eq(30)
    end

  end

  describe "accessors" do
    it "allows setting all attributes" do
      config.model = "test-model"
      config.temperature = 0.5
      config.api_key = "sk-test"
      config.max_iterations = 10
      config.timeout = 60
      config.namespace = "my-app"
      config.compact_model = "claude-haiku"

      expect(config.model).to eq("test-model")
      expect(config.temperature).to eq(0.5)
      expect(config.api_key).to eq("sk-test")
      expect(config.max_iterations).to eq(10)
      expect(config.timeout).to eq(60)
      expect(config.namespace).to eq("my-app")
      expect(config.compact_model).to eq("claude-haiku")
    end
  end

  describe "#validate!" do
    it "raises ConfigError when api_key is nil" do
      config.api_key = nil
      expect { config.validate! }.to raise_error(Mana::ConfigError, /API key is not configured/)
    end

    it "raises ConfigError when api_key is whitespace" do
      config.api_key = "   "
      expect { config.validate! }.to raise_error(Mana::ConfigError, /API key is not configured/)
    end

    it "returns true when api_key is set" do
      config.api_key = "sk-test"
      expect(config.validate!).to be true
    end
  end

  describe "MANA_TIMEOUT=0 validation" do
    it "raises on zero timeout via env var" do
      ENV["MANA_TIMEOUT"] = "0"
      expect { Mana::Config.new }.to raise_error(ArgumentError, /timeout must be a positive number/)
    ensure
      ENV.delete("MANA_TIMEOUT")
    end
  end
end
