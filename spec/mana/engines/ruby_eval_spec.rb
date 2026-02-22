# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Engines::Ruby do
  let(:b) { binding }
  let(:engine) { described_class.new(b) }

  # ── execute: basic expressions ──────────────────────────────

  describe "#execute" do
    it "evaluates simple arithmetic" do
      expect(engine.execute("1 + 2")).to eq(3)
    end

    it "returns string values" do
      expect(engine.execute("'hello ' + 'world'")).to eq("hello world")
    end

    it "returns nil for expressions that evaluate to nil" do
      expect(engine.execute("nil")).to be_nil
    end

    it "returns boolean values" do
      expect(engine.execute("3 > 2")).to eq(true)
      expect(engine.execute("1 > 5")).to eq(false)
    end

    it "returns float values" do
      expect(engine.execute("1.0 / 3")).to be_within(0.001).of(0.333)
    end

    it "returns arrays" do
      expect(engine.execute("[1, 'two', 3.0]")).to eq([1, "two", 3.0])
    end

    it "returns hashes" do
      expect(engine.execute("{ a: 1, b: 2 }")).to eq({ a: 1, b: 2 })
    end

    it "returns the result of the last expression in multi-line code" do
      result = engine.execute("a = 10\nb = 20\na + b")
      expect(result).to eq(30)
    end

    it "handles empty string input" do
      expect(engine.execute("")).to be_nil
    end

    it "handles unicode strings" do
      expect(engine.execute("'こんにちは'")).to eq("こんにちは")
    end
  end

  # ── variable bridging ───────────────────────────────────────

  describe "variable bridging" do
    it "sets a variable via execute and reads it back with read_var" do
      engine.execute("x = 42")
      expect(engine.read_var("x")).to eq(42)
    end

    it "writes a variable via write_var and reads it in execute" do
      engine.write_var("greeting", "hi")
      expect(engine.execute("greeting")).to eq("hi")
    end

    it "bridges complex types (arrays)" do
      engine.write_var("nums", [10, 20, 30])
      expect(engine.execute("nums.map { |n| n * 2 }")).to eq([20, 40, 60])
    end

    it "bridges complex types (hashes)" do
      engine.write_var("config", { host: "localhost", port: 3000 })
      expect(engine.execute("config[:port]")).to eq(3000)
    end

    it "reads pre-existing local variables from the caller binding" do
      data = [5, 10, 15]
      eng = described_class.new(binding)
      expect(eng.execute("data.sum")).to eq(30)
    end
  end

  # ── persistent context ──────────────────────────────────────

  describe "persistent context across calls" do
    it "retains variables set in a previous execute call" do
      engine.execute("counter = 1")
      engine.execute("counter += 1")
      expect(engine.execute("counter")).to eq(2)
    end

    it "retains method definitions across calls" do
      engine.execute("def double(n); n * 2; end")
      expect(engine.execute("double(21)")).to eq(42)
    end

    it "accumulates state across many calls" do
      engine.execute("items = []")
      engine.execute("items << 'a'")
      engine.execute("items << 'b'")
      engine.execute("items << 'c'")
      expect(engine.execute("items")).to eq(%w[a b c])
    end
  end

  # ── thread / instance isolation ─────────────────────────────

  describe "instance isolation" do
    it "two engines with separate bindings do not share variables" do
      b1 = binding
      b2 = binding
      e1 = described_class.new(b1)
      e2 = described_class.new(b2)

      e1.execute("iso_var = 'engine1'")
      expect { e2.execute("iso_var") }.to raise_error(NameError)
    end

    it "thread-local engines do not interfere" do
      results = []
      threads = 2.times.map do |i|
        Thread.new do
          local_b = binding
          eng = described_class.new(local_b)
          eng.execute("val = #{i * 100}")
          sleep 0.01 # yield to other thread
          results[i] = eng.execute("val")
        end
      end
      threads.each(&:join)
      expect(results).to eq([0, 100])
    end
  end

  # ── error handling ──────────────────────────────────────────

  describe "error handling" do
    it "raises SyntaxError on invalid Ruby code" do
      expect { engine.execute("def }{") }.to raise_error(SyntaxError)
    end

    it "raises RuntimeError on explicit raise" do
      expect { engine.execute("raise 'boom'") }.to raise_error(RuntimeError, "boom")
    end

    it "raises NameError for undefined variables" do
      expect { engine.execute("undefined_var_xyz") }.to raise_error(NameError)
    end

    it "raises ZeroDivisionError" do
      expect { engine.execute("1 / 0") }.to raise_error(ZeroDivisionError)
    end

    it "raises TypeError on incompatible operations" do
      expect { engine.execute("'string' + 42") }.to raise_error(TypeError)
    end

    it "propagates custom exception classes" do
      engine.execute("class MyError < StandardError; end")
      expect { engine.execute("raise MyError, 'custom'") }.to raise_error(StandardError, "custom")
    end
  end

  # ── type conversion / serialize ─────────────────────────────

  describe "serialize through execute results" do
    it "serializes nested arrays" do
      result = engine.execute("[[1, 2], [3, 4]]")
      expect(engine.serialize(result)).to eq([[1, 2], [3, 4]])
    end

    it "serializes nested hashes" do
      result = engine.execute("{ a: { b: 1 } }")
      expect(engine.serialize(result)).to eq({ a: { b: 1 } })
    end

    it "serializes complex objects to strings" do
      result = engine.execute("Object.new")
      serialized = engine.serialize(result)
      expect(serialized).to be_a(String)
      expect(serialized).to match(/Object/)
    end

    it "round-trips symbols" do
      result = engine.execute(":my_symbol")
      expect(engine.serialize(result)).to eq(:my_symbol)
    end
  end
end
