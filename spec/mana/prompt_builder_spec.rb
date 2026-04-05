# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::PromptBuilder do
  before do
    Mana.config.api_key = "test-key"
    Thread.current[:mana_context] = nil
    Thread.current[:mana_memory] = nil
    @tmpdir = Dir.mktmpdir("mana_test")
    Mana.config.memory_store = Mana::FileStore.new(@tmpdir)
  end

  after do
    Thread.current[:mana_context] = nil
    Thread.current[:mana_memory] = nil
    FileUtils.rm_rf(@tmpdir)
    Mana.reset!
  end

  describe "#build_context" do
    it "extracts multiple variable references from prompt" do
      b = binding.tap { |b|
        b.local_variable_set(:x, 10)
        b.local_variable_set(:y, 20)
        b.local_variable_set(:z, 30)
      }
      engine = Mana::Engine.new(b)
      ctx = engine.send(:build_context, "sum <x> and <y> and <z>")
      expect(ctx.keys).to contain_exactly("x", "y", "z")
      expect(ctx["x"]).to eq("10")
      expect(ctx["y"]).to eq("20")
      expect(ctx["z"]).to eq("30")
    end

    it "deduplicates repeated variable references" do
      b = binding.tap { |b| b.local_variable_set(:val, 5) }
      engine = Mana::Engine.new(b)
      ctx = engine.send(:build_context, "double <val> and add <val>")
      expect(ctx.keys).to eq(["val"])
    end

    it "skips variables that do not exist" do
      b = binding
      engine = Mana::Engine.new(b)
      ctx = engine.send(:build_context, "create <brand_new_var>")
      expect(ctx).to be_empty
    end

    it "handles prompts with no variable references" do
      b = binding
      engine = Mana::Engine.new(b)
      ctx = engine.send(:build_context, "just do something")
      expect(ctx).to be_empty
    end

    it "serializes complex variable values" do
      b = binding.tap { |b| b.local_variable_set(:data, { name: "Alice", scores: [90, 85] }) }
      engine = Mana::Engine.new(b)
      ctx = engine.send(:build_context, "analyze <data>")
      expect(ctx["data"]).to include("Alice")
      expect(ctx["data"]).to include("90")
    end
  end

  describe "#build_system_prompt" do
    it "includes core Mana identity and rules" do
      b = binding
      engine = Mana::Engine.new(b)
      prompt = engine.send(:build_system_prompt, {})
      expect(prompt).to include("You are Mana")
      expect(prompt).to include("read_var")
      expect(prompt).to include("write_var")
      expect(prompt).to include("done(result:")
    end

    it "includes variable context when provided" do
      b = binding
      engine = Mana::Engine.new(b)
      prompt = engine.send(:build_system_prompt, { "x" => "42", "name" => '"Alice"' })
      expect(prompt).to include("Current variable values:")
      expect(prompt).to include("x = 42")
      expect(prompt).to include('name = "Alice"')
    end

    it "excludes variable section when context is empty" do
      b = binding
      engine = Mana::Engine.new(b)
      prompt = engine.send(:build_system_prompt, {})
      expect(prompt).not_to include("Current variable values:")
    end

    # incognito removed from mana — now handled by claw

    it "includes context summaries when available" do
      context = Mana.memory
      context.summaries << "User prefers short answers"
      context.summaries << "Previous task completed successfully"

      b = binding
      engine = Mana::Engine.new(b)
      prompt = engine.send(:build_system_prompt, {})
      expect(prompt).to include("Previous conversation summary:")
      expect(prompt).to include("User prefers short answers")
      expect(prompt).to include("Previous task completed successfully")
    end

    it "includes registered prompt sections" do
      Mana.register_prompt_section do
        "Long-term memories (persistent background context):\n- User likes Ruby"
      end

      b = binding
      engine = Mana::Engine.new(b)
      prompt = engine.send(:build_system_prompt, {})
      expect(prompt).to include("Long-term memories")
      expect(prompt).to include("User likes Ruby")
    end

    it "excludes memory sections when no summaries or prompt sections" do
      b = binding
      engine = Mana::Engine.new(b)
      prompt = engine.send(:build_system_prompt, {})
      expect(prompt).not_to include("Previous conversation summary:")
      expect(prompt).not_to include("Long-term memories")
    end

    it "skips nil prompt sections" do
      Mana.register_prompt_section { nil }

      b = binding
      engine = Mana::Engine.new(b)
      prompt = engine.send(:build_system_prompt, {})
      expect(prompt).not_to include("Long-term memories")
    end
  end
end
