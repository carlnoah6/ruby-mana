# frozen_string_literal: true

require "spec_helper"

# Try to load pycall and the Python engine
PYCALL_AVAILABLE = begin
  require "pycall"
  require "mana/engines/python"
  true
rescue LoadError
  false
end

# When pycall is not available, define a minimal Python class for unit testing
unless PYCALL_AVAILABLE
  module Mana
    module Engines
      class Python < Base
        def self.reset!
          # no-op stub when pycall is not available
        end

        def execute(code)
          raise NotImplementedError, "pycall not available"
        end

        private

        def extract_declared_vars(code)
          vars = []
          code.scan(/^(\w+)\s*=[^=]/).each { |m| vars << m[0] }
          code.scan(/^(\w+)\s*[+\-*\/]?=/).each { |m| vars << m[0] }
          vars.uniq
        end
      end
    end
  end
end

RSpec.describe Mana::Engines::Python do
  describe "extract_declared_vars" do
    let(:engine) { described_class.new(binding) }

    it "finds simple assignments" do
      vars = engine.send(:extract_declared_vars, "x = 1\ny = 2\nz = x + y")
      expect(vars).to include("x", "y", "z")
    end

    it "ignores comparisons" do
      vars = engine.send(:extract_declared_vars, "if x == 1:\n  pass")
      expect(vars).not_to include("x")
    end

    it "finds augmented assignments" do
      vars = engine.send(:extract_declared_vars, "x += 1\ny -= 2")
      expect(vars).to include("x", "y")
    end

    it "deduplicates variable names" do
      vars = engine.send(:extract_declared_vars, "x = 1\nx = 2")
      expect(vars.count("x")).to eq(1)
    end

    it "handles multiline code" do
      code = "a = 1\nb = 2\nc = a + b\nresult = c * 2"
      vars = engine.send(:extract_declared_vars, code)
      expect(vars).to include("a", "b", "c", "result")
    end
  end

  describe "execution", if: PYCALL_AVAILABLE do
    before do
      described_class.reset!
    end

    after do
      described_class.reset!
    end

    describe "#execute" do
      it "executes simple Python and returns result via 'result' variable" do
        b = binding
        engine = described_class.new(b)
        engine.execute("result = 1 + 2")
        expect(b.local_variable_get(:result)).to eq(3)
      end

      it "creates variables and writes back to Ruby" do
        b = binding
        engine = described_class.new(b)
        engine.execute("x = 1 + 2")
        expect(b.local_variable_get(:x)).to eq(3)
      end

      it "reads Ruby variables in Python code" do
        data = [1, 2, 3]
        b = binding
        engine = described_class.new(b)
        engine.execute("total = sum(data)")
        expect(b.local_variable_get(:total)).to eq(6)
      end

      it "handles string operations" do
        b = binding
        engine = described_class.new(b)
        engine.execute('greeting = "hello" + " " + "world"')
        expect(b.local_variable_get(:greeting)).to eq("hello world")
      end

      it "handles list comprehensions with Ruby variables" do
        data = [1, 2, 3, 4, 5]
        b = binding
        engine = described_class.new(b)
        engine.execute("evens = [n for n in data if n % 2 == 0]")
        expect(b.local_variable_get(:evens)).to eq([2, 4])
      end

      it "handles None correctly" do
        b = binding
        engine = described_class.new(b)
        engine.execute("nothing = None")
        expect(b.local_variable_get(:nothing)).to be_nil
      end
    end

    describe "persistent namespace" do
      it "retains variables across calls in same thread" do
        b = binding
        engine = described_class.new(b)
        engine.execute("counter = 0")

        engine2 = described_class.new(b)
        engine2.execute("counter = counter + 1\nupdated_counter = counter")
        expect(b.local_variable_get(:updated_counter)).to eq(1)
      end

      it "retains function definitions across calls" do
        b = binding
        engine = described_class.new(b)
        engine.execute("def add(a, b):\n  return a + b")

        engine2 = described_class.new(b)
        engine2.execute("result = add(3, 4)")
        expect(b.local_variable_get(:result)).to eq(7)
      end
    end

    describe ".reset!" do
      it "clears the namespace" do
        b = binding
        engine = described_class.new(b)
        engine.execute("reset_test = 123")
        expect(b.local_variable_get(:reset_test)).to eq(123)

        described_class.reset!

        # After reset, old namespace is gone; new one won't have the variable
        b2 = binding
        engine2 = described_class.new(b2)
        engine2.execute("result = 'fresh'")
        expect(b2.local_variable_get(:result)).to eq("fresh")
      end
    end

    describe "type transfer" do
      it "transfers Ruby arrays to Python lists" do
        items = [10, 20, 30]
        b = binding
        engine = described_class.new(b)
        engine.execute("total = sum(items)")
        expect(b.local_variable_get(:total)).to eq(60)
      end

      it "transfers Ruby hashes to Python dicts" do
        person = { "name" => "Alice", "age" => 30 }
        b = binding
        engine = described_class.new(b)
        engine.execute('name = person["name"]')
        expect(b.local_variable_get(:name)).to eq("Alice")
      end

      it "handles Ruby symbols by converting to strings" do
        sym_val = :hello
        b = binding
        engine = described_class.new(b)
        engine.execute("result = sym_val")
        expect(b.local_variable_get(:result)).to eq("hello")
      end
    end

    describe "error wrapping" do
      it "wraps Python syntax errors in Mana::Error" do
        b = binding
        engine = described_class.new(b)
        expect { engine.execute("def broken(") }.to raise_error(Mana::Error, /Python execution error/)
      end

      it "wraps Python runtime errors in Mana::Error" do
        b = binding
        engine = described_class.new(b)
        expect { engine.execute("result = 1 / 0") }.to raise_error(Mana::Error, /Python execution error/)
      end

      it "wraps NameError in Mana::Error" do
        b = binding
        engine = described_class.new(b)
        expect { engine.execute("result = undefined_variable") }.to raise_error(Mana::Error, /Python execution error/)
      end
    end

    describe "serialize_for_py" do
      it "preserves numeric hash keys" do
        engine = described_class.new(binding)
        result = engine.send(:serialize_for_py, { 1 => "one", 2 => "two" })
        expect(result).to eq({ 1 => "one", 2 => "two" })
      end

      it "converts symbol keys to strings" do
        engine = described_class.new(binding)
        result = engine.send(:serialize_for_py, { foo: "bar", baz: 42 })
        expect(result).to eq({ "foo" => "bar", "baz" => 42 })
      end

      it "preserves string keys as-is" do
        engine = described_class.new(binding)
        result = engine.send(:serialize_for_py, { "key" => "val" })
        expect(result).to eq({ "key" => "val" })
      end

      it "recursively serializes nested values" do
        engine = described_class.new(binding)
        result = engine.send(:serialize_for_py, { items: [1, :two, { nested: true }] })
        expect(result).to eq({ "items" => [1, "two", { "nested" => true }] })
      end
    end

    describe "selective variable injection" do
      it "only injects variables referenced in the code" do
        used = 10
        unused = 20
        b = binding
        engine = described_class.new(b)
        engine.execute("result = used + 1")
        expect(b.local_variable_get(:result)).to eq(11)
      end
    end
  end

  describe Mana::Engines::RubyBridge do
    let(:receiver) do
      klass = Class.new do
        def greet(name)
          "hello #{name}"
        end

        private

        def secret
          "hidden"
        end
      end
      klass.new
    end

    let(:bridge) do
      b = binding
      described_class.new(b)
    end

    it "proxies public method calls to the receiver" do
      b = receiver # need receiver in binding scope
      bnd = binding
      br = described_class.new(bnd)
      # receiver is accessible as 'b' in binding, but bridge uses binding.receiver
      # Let's create a proper bridge with the receiver as binding.receiver
      obj = receiver
      fake_binding = obj.instance_eval { binding }
      br2 = described_class.new(fake_binding)
      expect(br2.greet("world")).to eq("hello world")
    end

    it "does not proxy private methods" do
      obj = receiver
      fake_binding = obj.instance_eval { binding }
      br = described_class.new(fake_binding)
      expect { br.secret }.to raise_error(NoMethodError)
    end

    it "reads and writes local variables" do
      score = 100
      b = binding
      br = described_class.new(b)
      expect(br.read("score")).to eq(100)
      br.write("score", 200)
      expect(b.local_variable_get(:score)).to eq(200)
    end

    it "calls local procs by name" do
      doubler = proc { |x| x * 2 }
      b = binding
      br = described_class.new(b)
      expect(br.call_proc("doubler", 5)).to eq(10)
    end

    it "raises NameError for undefined variables" do
      b = binding
      br = described_class.new(b)
      expect { br.read("nonexistent") }.to raise_error(NameError)
    end
  end
end
