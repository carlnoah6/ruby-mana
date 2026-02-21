# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Config do
  subject(:config) { described_class.new }

  describe "defaults" do
    it "sets model to claude-sonnet-4" do
      expect(config.model).to eq("claude-sonnet-4-20250514")
    end

    it "sets temperature to 0" do
      expect(config.temperature).to eq(0)
    end

    it "reads api_key from ENV" do
      expect(config.api_key).to eq(ENV["ANTHROPIC_API_KEY"])
    end

    it "sets max_iterations to 50" do
      expect(config.max_iterations).to eq(50)
    end

    it "sets base_url to anthropic" do
      expect(config.base_url).to eq("https://api.anthropic.com")
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

  describe "accessors" do
    it "allows setting all attributes" do
      config.model = "test-model"
      config.temperature = 0.5
      config.api_key = "sk-test"
      config.max_iterations = 10
      config.namespace = "my-app"
      config.compact_model = "claude-haiku"

      expect(config.model).to eq("test-model")
      expect(config.temperature).to eq(0.5)
      expect(config.api_key).to eq("sk-test")
      expect(config.max_iterations).to eq(10)
      expect(config.namespace).to eq("my-app")
      expect(config.compact_model).to eq("claude-haiku")
    end
  end
end
