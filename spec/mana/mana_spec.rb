# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana do
  before do
    Mana.reset!
    Mana.config.api_key = "test-key"
  end

  after { Mana.reset! }

  describe ".configure" do
    it "yields config and returns it" do
      result = Mana.configure do |c|
        c.model = "test-model"
        c.temperature = 0.8
      end

      expect(result).to be_a(Mana::Config)
      expect(Mana.config.model).to eq("test-model")
      expect(Mana.config.temperature).to eq(0.8)
    end

    it "returns config without block" do
      expect(Mana.configure).to be_a(Mana::Config)
    end
  end

  describe ".model=" do
    it "sets the model on config" do
      Mana.model = "claude-haiku"
      expect(Mana.config.model).to eq("claude-haiku")
    end
  end

  describe ".reset!" do
    it "resets config to defaults" do
      Mana.config.model = "custom"
      Mana.config.temperature = 0.9
      Mana.reset!

      expect(Mana.config.model).to eq("claude-sonnet-4-6")
      expect(Mana.config.temperature).to eq(0)
    end

    it "clears thread-local memory" do
      Thread.current[:mana_memory] = "something"
      Mana.reset!
      expect(Thread.current[:mana_memory]).to be_nil
    end

  end

  describe ".memory" do
    it "returns current thread memory" do
      mem = Mana.memory
      expect(mem).to be_a(Mana::Memory)
    end
  end

  describe ".incognito" do
    it "runs block in incognito mode" do
      was_incognito = nil
      Mana.incognito do
        was_incognito = Mana::Memory.incognito?
      end
      expect(was_incognito).to be true
    end

    it "restores non-incognito after block" do
      Mana.incognito { }
      expect(Mana::Memory.incognito?).to be false
    end
  end


  describe ".source" do
    it "delegates to Compiler.source" do
      expect(Mana::Compiler).to receive(:source).with(:foo, owner: nil).and_return("def foo; end")
      expect(Mana.source(:foo)).to eq("def foo; end")
    end
  end

  describe ".cache_dir=" do
    it "delegates to Compiler.cache_dir=" do
      expect(Mana::Compiler).to receive(:cache_dir=).with("/tmp/custom_cache")
      Mana.cache_dir = "/tmp/custom_cache"
    end
  end

  describe "error classes" do
    it "defines Error as StandardError subclass" do
      expect(Mana::Error.ancestors).to include(StandardError)
    end

    it "defines MaxIterationsError" do
      expect(Mana::MaxIterationsError.ancestors).to include(Mana::Error)
    end

    it "defines LLMError" do
      expect(Mana::LLMError.ancestors).to include(Mana::Error)
    end
  end
end
