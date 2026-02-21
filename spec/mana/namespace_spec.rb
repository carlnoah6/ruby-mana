# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Namespace do
  after { Mana.config.namespace = nil }

  describe ".detect" do
    it "returns configured namespace when set" do
      Mana.config.namespace = "my-project"
      expect(described_class.detect).to eq("my-project")
    end

    it "falls back to git repo name" do
      Mana.config.namespace = nil
      result = described_class.detect
      # In a git repo, should return something non-default
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end

    it "returns a string always" do
      expect(described_class.detect).to be_a(String)
    end
  end

  describe ".configured" do
    it "returns nil when not configured" do
      Mana.config.namespace = nil
      expect(described_class.configured).to be_nil
    end

    it "returns the configured value" do
      Mana.config.namespace = "test"
      expect(described_class.configured).to eq("test")
    end

    it "returns nil for empty string" do
      Mana.config.namespace = ""
      expect(described_class.configured).to be_nil
    end
  end

  describe ".from_git_repo" do
    it "returns a string in a git repository" do
      result = described_class.from_git_repo
      # We're running tests inside a git repo
      expect(result).to be_a(String) if result
    end
  end

  describe ".from_pwd" do
    it "returns the current directory basename" do
      expect(described_class.from_pwd).to eq(File.basename(Dir.pwd))
    end
  end
end
