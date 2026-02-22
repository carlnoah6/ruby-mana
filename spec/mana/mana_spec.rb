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

      expect(Mana.config.model).to eq("claude-sonnet-4-20250514")
      expect(Mana.config.temperature).to eq(0)
    end

    it "clears thread-local memory" do
      Thread.current[:mana_memory] = "something"
      Mana.reset!
      expect(Thread.current[:mana_memory]).to be_nil
    end

    it "clears custom effects" do
      Mana.define_effect(:test_effect, description: "test") { "result" }
      expect(Mana::EffectRegistry.tool_definitions).not_to be_empty
      Mana.reset!
      expect(Mana::EffectRegistry.tool_definitions).to be_empty
    end

    it "resets JavaScript V8 context" do
      require "mana/engines/javascript"
      # Get a reference to the current JS context
      ctx = Mana::Engines::JavaScript.context
      ctx.eval("var jsResetTest = 42")
      expect(ctx.eval("jsResetTest")).to eq(42)

      Mana.reset!

      # After reset, the old context should be disposed
      expect { ctx.eval("jsResetTest") }.to raise_error(MiniRacer::Error)
      # And a new context should not have the old variable
      new_ctx = Mana::Engines::JavaScript.context
      expect(new_ctx).not_to eq(ctx)
    end

    it "clears last engine context" do
      Thread.current[:mana_last_engine] = "javascript"
      Mana.reset!
      expect(Thread.current[:mana_last_engine]).to be_nil
    end

    it "clears the ObjectRegistry" do
      Mana::ObjectRegistry.current.register(Object.new)
      expect(Mana::ObjectRegistry.current.size).to eq(1)
      Mana.reset!
      expect(Mana::ObjectRegistry.current.size).to eq(0)
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

  describe ".define_effect / .undefine_effect" do
    after { Mana::EffectRegistry.clear! }

    it "registers and removes custom effects" do
      Mana.define_effect(:my_tool, description: "does stuff") { |params| params }
      expect(Mana::EffectRegistry.tool_definitions.map { |t| t[:name] }).to include("my_tool")

      Mana.undefine_effect(:my_tool)
      expect(Mana::EffectRegistry.tool_definitions.map { |t| t[:name] }).not_to include("my_tool")
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
