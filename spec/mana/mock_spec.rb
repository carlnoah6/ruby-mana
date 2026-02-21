# frozen_string_literal: true

require "spec_helper"
require "mana/test"

RSpec.describe Mana::Mock do
  before do
    Mana.config.api_key = "test-key"
    Thread.current[:mana_memory] = nil
    Thread.current[:mana_incognito] = nil
    Thread.current[:mana_mock] = nil
    @tmpdir = Dir.mktmpdir("mana_test")
    Mana.config.memory_store = Mana::FileStore.new(@tmpdir)
  end

  after do
    Thread.current[:mana_memory] = nil
    Thread.current[:mana_incognito] = nil
    Thread.current[:mana_mock] = nil
    FileUtils.rm_rf(@tmpdir)
    Mana.reset!
  end

  describe "Mana.mock (block mode)" do
    it "sets variables via stub values" do
      result_bugs = nil
      result_score = nil

      Mana.mock do
        prompt "analyze", bugs: ["XSS"], score: 8.5

        b = binding
        Mana::Engine.run("analyze <code> for issues", b)
        result_bugs = b.local_variable_get(:bugs)
        result_score = b.local_variable_get(:score)
      end

      expect(result_bugs).to eq(["XSS"])
      expect(result_score).to eq(8.5)
    end

    it "returns _return value from stub" do
      result = nil

      Mana.mock do
        prompt "translate", _return: "hello"

        b = binding
        result = Mana::Engine.run("translate this text", b)
      end

      expect(result).to eq("hello")
    end

    it "returns first value when no _return specified" do
      result = nil

      Mana.mock do
        prompt "analyze", score: 9.0

        b = binding
        result = Mana::Engine.run("analyze this", b)
      end

      expect(result).to eq(9.0)
    end

    it "matches with substring" do
      output = nil

      Mana.mock do
        prompt "translate", output: "hola"

        b = binding
        Mana::Engine.run("please translate <text> to Spanish", b)
        output = b.local_variable_get(:output)
      end

      expect(output).to eq("hola")
    end

    it "matches with regex" do
      output = nil

      Mana.mock do
        prompt(/translate.*Spanish/i, output: "hola")

        b = binding
        Mana::Engine.run("translate <text> to Spanish please", b)
        output = b.local_variable_get(:output)
      end

      expect(output).to eq("hola")
    end

    it "supports block-based dynamic values" do
      output = nil

      Mana.mock do
        prompt("translate") do |prompt_text|
          if prompt_text.include?("Spanish")
            { output: "hola" }
          else
            { output: "hello" }
          end
        end

        b = binding
        Mana::Engine.run("translate to Spanish", b)
        output = b.local_variable_get(:output)
      end

      expect(output).to eq("hola")
    end

    it "raises MockError for unmatched prompts" do
      expect {
        Mana.mock do
          prompt "translate", output: "hi"

          b = binding
          Mana::Engine.run("unrelated prompt about weather", b)
        end
      }.to raise_error(Mana::MockError, /No mock matched/)
    end

    it "includes helpful message in MockError" do
      expect {
        Mana.mock do
          b = binding
          Mana::Engine.run("analyze code", b)
        end
      }.to raise_error(Mana::MockError, /mock_prompt/)
    end

    it "cleans up mock mode after block" do
      Mana.mock do
        prompt "test", result: "ok"
      end

      expect(Mana.mock_active?).to be false
    end

    it "cleans up mock mode even on error" do
      begin
        Mana.mock do
          raise "boom"
        end
      rescue RuntimeError
        # expected
      end

      expect(Mana.mock_active?).to be false
    end

    it "does not make any API calls" do
      Mana.mock do
        prompt "compute", result: 42

        b = binding
        Mana::Engine.run("compute something", b)
      end

      expect(WebMock).not_to have_requested(:post, "https://api.anthropic.com/v1/messages")
    end

    it "matches first matching stub" do
      result = nil

      Mana.mock do
        prompt "analyze", result: "first"
        prompt "analyze code", result: "second"

        b = binding
        result = Mana::Engine.run("analyze code", b)
      end

      expect(result).to eq("first")
    end
  end

  describe "Mana.mock! / Mana.unmock!" do
    it "activates and deactivates mock mode" do
      expect(Mana.mock_active?).to be false

      Mana.mock!
      expect(Mana.mock_active?).to be true

      Mana.unmock!
      expect(Mana.mock_active?).to be false
    end

    it "allows registering stubs via current_mock" do
      Mana.mock!
      Mana.current_mock.prompt("test", value: 42)

      b = binding
      Mana::Engine.run("test this", b)
      expect(b.local_variable_get(:value)).to eq(42)

      Mana.unmock!
    end
  end

  describe "thread safety" do
    it "mock mode is thread-local" do
      Mana.mock!
      Mana.current_mock.prompt("test", value: 1)

      other_thread_mock = nil
      t = Thread.new { other_thread_mock = Mana.mock_active? }
      t.join

      expect(Mana.mock_active?).to be true
      expect(other_thread_mock).to be false

      Mana.unmock!
    end
  end

  describe "memory interaction" do
    it "records mock interactions in short-term memory" do
      Mana.mock!
      Mana.current_mock.prompt("test", value: 42)

      b = binding
      Mana::Engine.run("test prompt", b)

      memory = Mana.memory
      expect(memory.short_term.size).to eq(2)
      expect(memory.short_term[0][:role]).to eq("user")
      expect(memory.short_term[0][:content]).to eq("test prompt")
      expect(memory.short_term[1][:role]).to eq("assistant")

      Mana.unmock!
    end

    it "skips memory in incognito mode" do
      Mana::Memory.incognito do
        Mana.mock!
        Mana.current_mock.prompt("test", value: 42)

        b = binding
        Mana::Engine.run("test prompt", b)

        Mana.unmock!
      end

      memory = Mana.memory
      expect(memory.short_term).to be_empty
    end
  end

  describe "Mana.reset!" do
    it "clears mock state" do
      Mana.mock!
      expect(Mana.mock_active?).to be true

      Mana.reset!
      expect(Mana.mock_active?).to be false
    end
  end
end

RSpec.describe Mana::TestHelpers do
  before do
    Mana.config.api_key = "test-key"
    Thread.current[:mana_memory] = nil
    Thread.current[:mana_incognito] = nil
    Thread.current[:mana_mock] = nil
    @tmpdir = Dir.mktmpdir("mana_test")
    Mana.config.memory_store = Mana::FileStore.new(@tmpdir)
  end

  after do
    Thread.current[:mana_memory] = nil
    Thread.current[:mana_incognito] = nil
    Thread.current[:mana_mock] = nil
    FileUtils.rm_rf(@tmpdir)
    Mana.reset!
  end

  describe "mock_prompt helper" do
    it "raises when mock mode is not active" do
      helper = Object.new
      helper.extend(Mana::TestHelpers)

      expect {
        helper.mock_prompt("test", value: 1)
      }.to raise_error(Mana::MockError, /mock mode not active/)
    end

    it "registers stubs when mock is active" do
      helper = Object.new
      helper.extend(Mana::TestHelpers)

      Mana.mock!
      helper.mock_prompt("analyze", bugs: ["SQL injection"], score: 7.0)

      b = binding
      Mana::Engine.run("analyze this code", b)
      expect(b.local_variable_get(:bugs)).to eq(["SQL injection"])
      expect(b.local_variable_get(:score)).to eq(7.0)

      Mana.unmock!
    end

    it "supports regex patterns" do
      helper = Object.new
      helper.extend(Mana::TestHelpers)

      Mana.mock!
      helper.mock_prompt(/translate.*to\s+(\w+)/, output: "bonjour")

      b = binding
      Mana::Engine.run("translate hello to French", b)
      expect(b.local_variable_get(:output)).to eq("bonjour")

      Mana.unmock!
    end

    it "supports block-based responses" do
      helper = Object.new
      helper.extend(Mana::TestHelpers)

      Mana.mock!
      helper.mock_prompt("compute") do |prompt_text|
        { result: prompt_text.include?("sum") ? 10 : 0 }
      end

      b = binding
      Mana::Engine.run("compute the sum", b)
      expect(b.local_variable_get(:result)).to eq(10)

      Mana.unmock!
    end
  end
end
