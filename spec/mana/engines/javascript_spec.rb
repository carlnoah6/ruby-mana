# frozen_string_literal: true

require "spec_helper"
require "mana/engines/javascript"

RSpec.describe Mana::Engines::JavaScript do
  before do
    described_class.reset!
  end

  after do
    described_class.reset!
  end

  def run_js(code, bnd = binding)
    engine = described_class.new(bnd)
    engine.execute(code)
  end

  describe "#execute" do
    it "executes simple JS and returns result" do
      result = run_js("1 + 2")
      expect(result).to eq(3)
    end

    it "creates variables with const and writes back to Ruby" do
      b = binding
      engine = described_class.new(b)
      engine.execute("const x = 1 + 2")
      expect(b.local_variable_get(:x)).to eq(3)
    end

    it "creates variables with let and writes back to Ruby" do
      b = binding
      engine = described_class.new(b)
      engine.execute("let y = 'hello'")
      expect(b.local_variable_get(:y)).to eq("hello")
    end

    it "creates variables with var and writes back to Ruby" do
      b = binding
      engine = described_class.new(b)
      engine.execute("var z = true")
      expect(b.local_variable_get(:z)).to eq(true)
    end

    it "reads Ruby variables in JS code" do
      data = [1, 2, 3]
      b = binding
      engine = described_class.new(b)
      engine.execute("const sum = data.reduce((a, b) => a + b, 0)")
      expect(b.local_variable_get(:sum)).to eq(6)
    end

    it "reads Ruby hash as JS object" do
      config = { "name" => "test", "count" => 42 }
      b = binding
      engine = described_class.new(b)
      result = engine.execute("config.name")
      expect(result).to eq("test")
    end

    it "handles array filtering from Ruby variables" do
      data = [1, -2, 3, -4, 5]
      b = binding
      engine = described_class.new(b)
      engine.execute("const positives = data.filter(n => n > 0)")
      expect(b.local_variable_get(:positives)).to eq([1, 3, 5])
    end

    it "returns the evaluation result" do
      result = run_js("2 * 21")
      expect(result).to eq(42)
    end

    it "handles string operations" do
      b = binding
      engine = described_class.new(b)
      engine.execute('const greeting = "hello" + " " + "world"')
      expect(b.local_variable_get(:greeting)).to eq("hello world")
    end

    it "handles null/undefined correctly" do
      b = binding
      engine = described_class.new(b)
      engine.execute("const nothing = null")
      expect(b.local_variable_get(:nothing)).to be_nil
    end
  end

  describe "persistent context" do
    it "retains variables across calls in same thread" do
      b = binding
      engine = described_class.new(b)
      engine.execute("let counter = 0")

      engine2 = described_class.new(b)
      engine2.execute("counter += 1; var updatedCounter = counter")
      expect(b.local_variable_get(:updatedCounter)).to eq(1)
    end

    it "retains function definitions across calls" do
      b = binding
      engine = described_class.new(b)
      engine.execute("function add(a, b) { return a + b }")

      engine2 = described_class.new(b)
      result = engine2.execute("add(3, 4)")
      expect(result).to eq(7)
    end
  end

  describe "thread isolation" do
    it "uses separate V8 contexts per thread" do
      described_class.reset!

      b1 = binding
      engine1 = described_class.new(b1)
      engine1.execute("var threadVal = 'main'")

      thread_result = nil
      t = Thread.new do
        b2 = binding
        engine2 = described_class.new(b2)
        engine2.execute("var threadVal = 'other'")
        thread_result = described_class.context.eval("threadVal")
        described_class.reset!
      end
      t.join

      main_val = described_class.context.eval("threadVal")
      expect(main_val).to eq("main")
      expect(thread_result).to eq("other")
    end
  end

  describe ".reset!" do
    it "disposes and clears the V8 context" do
      run_js("var resetTest = 123")
      expect(described_class.context.eval("resetTest")).to eq(123)

      described_class.reset!

      expect { described_class.context.eval("resetTest") }.to raise_error(MiniRacer::RuntimeError)
    end
  end

  describe "type transfer" do
    it "transfers Ruby arrays to JS arrays" do
      items = [10, 20, 30]
      b = binding
      engine = described_class.new(b)
      engine.execute("const total = items.reduce((a, b) => a + b, 0)")
      expect(b.local_variable_get(:total)).to eq(60)
    end

    it "transfers Ruby hashes to JS objects" do
      person = { "name" => "Alice", "age" => 30 }
      b = binding
      engine = described_class.new(b)
      engine.execute("const name = person.name")
      expect(b.local_variable_get(:name)).to eq("Alice")
    end

    it "transfers nested structures" do
      data = { "users" => [{ "name" => "Bob" }, { "name" => "Carol" }] }
      b = binding
      engine = described_class.new(b)
      engine.execute("const first = data.users[0].name")
      expect(b.local_variable_get(:first)).to eq("Bob")
    end

    it "handles Ruby symbols by converting to strings" do
      sym_val = :hello
      b = binding
      engine = described_class.new(b)
      result = engine.execute("sym_val")
      expect(result).to eq("hello")
    end
  end

  describe "error handling" do
    it "raises on JS syntax errors" do
      expect { run_js("const = ;") }.to raise_error(MiniRacer::Error)
    end

    it "raises on JS runtime errors" do
      expect { run_js("undeclaredVar.property") }.to raise_error(MiniRacer::RuntimeError)
    end

    it "skips unserializable Ruby variables gracefully" do
      b = binding
      b.local_variable_set(:good, 42)
      # Complex objects get serialized to string via Base#serialize
      engine = described_class.new(b)
      # Should not raise
      expect { engine.execute("const val = good + 1") }.not_to raise_error
    end
  end

  describe "selective variable injection" do
    it "only injects variables referenced in the code" do
      b = binding
      b.local_variable_set(:used_var, 10)
      b.local_variable_set(:unused_var, 20)
      engine = described_class.new(b)
      result = engine.execute("used_var + 1")
      expect(result).to eq(11)
      # unused_var should NOT be in the JS context
      expect { described_class.context.eval("unused_var") }.to raise_error(MiniRacer::RuntimeError)
    end

    it "does not inject variables that are substrings of other identifiers" do
      b = binding
      b.local_variable_set(:data, [1, 2, 3])
      engine = described_class.new(b)
      # 'metadata' contains 'data' as substring, but data should NOT be injected
      engine.execute("const metadata = 'info'")
      # data should not be in JS context since only 'metadata' was referenced
      expect { described_class.context.eval("data") }.to raise_error(MiniRacer::RuntimeError)
    end

    it "does not pollute JS context with unrelated binding vars" do
      b = binding
      b.local_variable_set(:alpha, 1)
      b.local_variable_set(:beta, 2)
      b.local_variable_set(:gamma, 3)
      engine = described_class.new(b)
      engine.execute("const sum = alpha + gamma")
      # beta was not referenced, should not exist in JS
      expect { described_class.context.eval("beta") }.to raise_error(MiniRacer::RuntimeError)
    end
  end
end
