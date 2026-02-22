# frozen_string_literal: true

require "spec_helper"
require "mana/engines/javascript"

RSpec.describe Mana::Engines::JavaScript do
  before do
    described_class.reset!
    Mana::EffectRegistry.clear!
  end

  after do
    described_class.reset!
    Mana::EffectRegistry.clear!
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

  describe "bidirectional calling: ruby.read / ruby.write" do
    it "reads a Ruby variable from JS via ruby.read" do
      x = 42
      b = binding
      engine = described_class.new(b)
      result = engine.execute('ruby.read("x")')
      expect(result).to eq(42)
    end

    it "writes a Ruby variable from JS via ruby.write" do
      x = 0
      b = binding
      engine = described_class.new(b)
      engine.execute('ruby.write("x", 99)')
      expect(b.local_variable_get(:x)).to eq(99)
    end

    it "reads and writes in a single JS expression" do
      counter = 10
      b = binding
      engine = described_class.new(b)
      engine.execute('ruby.write("counter", ruby.read("counter") + 5)')
      expect(b.local_variable_get(:counter)).to eq(15)
    end

    it "reads complex types (arrays, hashes)" do
      data = [1, 2, 3]
      b = binding
      engine = described_class.new(b)
      result = engine.execute('ruby.read("data")')
      expect(result).to eq([1, 2, 3])
    end

    it "returns null for undefined variables" do
      b = binding
      engine = described_class.new(b)
      result = engine.execute('ruby.read("nonexistent")')
      expect(result).to be_nil
    end
  end

  describe "bidirectional calling: Ruby methods from JS" do
    let(:test_class) do
      Class.new do
        def greet(name)
          "Hello, #{name}!"
        end

        def add(a, b)
          a + b
        end

        def get_data
          { "items" => [1, 2, 3], "count" => 3 }
        end
      end
    end

    it "calls a Ruby method with one argument" do
      obj = test_class.new
      b = obj.instance_eval { binding }
      engine = described_class.new(b)
      result = engine.execute('ruby.greet("world")')
      expect(result).to eq("Hello, world!")
    end

    it "calls a Ruby method with multiple arguments" do
      obj = test_class.new
      b = obj.instance_eval { binding }
      engine = described_class.new(b)
      result = engine.execute("ruby.add(10, 20)")
      expect(result).to eq(30)
    end

    it "returns complex types from Ruby methods" do
      obj = test_class.new
      b = obj.instance_eval { binding }
      engine = described_class.new(b)
      result = engine.execute('JSON.stringify(ruby.get_data())')
      parsed = JSON.parse(result)
      expect(parsed["items"]).to eq([1, 2, 3])
      expect(parsed["count"]).to eq(3)
    end

    it "uses Ruby method results in JS computation" do
      obj = test_class.new
      b = obj.instance_eval { binding }
      engine = described_class.new(b)
      engine.execute("const doubled = ruby.add(5, 5) * 2")
      expect(b.local_variable_get(:doubled)).to eq(20)
    end
  end

  describe "bidirectional calling: Mana effects from JS" do
    it "calls a registered effect from JS" do
      Mana.define_effect :double_it, description: "Double a number" do |n:|
        n.to_i * 2
      end

      b = binding
      engine = described_class.new(b)
      result = engine.execute("ruby.double_it(21)")
      expect(result).to eq(42)
    end

    it "calls an effect with multiple params" do
      Mana.define_effect :concat, description: "Concat strings" do |a:, b:|
        "#{a}-#{b}"
      end

      b = binding
      engine = described_class.new(b)
      result = engine.execute('ruby.concat("hello", "world")')
      expect(result).to eq("hello-world")
    end

    it "calls an effect with a hash argument" do
      Mana.define_effect :lookup, description: "Lookup by key" do |key:|
        { "a" => 1, "b" => 2 }[key]
      end

      b = binding
      engine = described_class.new(b)
      # Pass a JS object — mini_racer converts it to a Ruby Hash
      result = engine.execute('ruby.lookup({"key": "a"})')
      expect(result).to eq(1)
    end

    it "uses effect results in JS computation" do
      Mana.define_effect :fetch_price, description: "Get price" do |item:|
        case item
        when "apple" then 1.5
        when "banana" then 0.75
        else 0
        end
      end

      b = binding
      engine = described_class.new(b)
      engine.execute('const total = ruby.fetch_price("apple") + ruby.fetch_price("banana")')
      expect(b.local_variable_get(:total)).to eq(2.25)
    end
  end

  describe "bidirectional calling: error handling" do
    let(:error_class) do
      Class.new do
        def fail_hard
          raise "intentional error"
        end
      end
    end

    it "propagates Ruby exceptions to JS" do
      obj = error_class.new
      b = obj.instance_eval { binding }
      engine = described_class.new(b)
      expect { engine.execute("ruby.fail_hard()") }.to raise_error(RuntimeError, /intentional error/)
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

    it "retains ruby.* callbacks across calls" do
      x = 1
      b = binding
      engine = described_class.new(b)
      engine.execute('ruby.write("x", 10)')

      engine2 = described_class.new(b)
      result = engine2.execute('ruby.read("x")')
      expect(result).to eq(10)
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

    it "clears attached callbacks so they can be re-attached" do
      b = binding
      engine = described_class.new(b)
      engine.execute('ruby.read("b")') # attaches callbacks

      described_class.reset!

      # After reset, new context should get fresh callbacks
      b2 = binding
      engine2 = described_class.new(b2)
      expect { engine2.execute('ruby.read("b2")') }.not_to raise_error
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
      engine = described_class.new(b)
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

    it "uses word-boundary matching to avoid substring injection" do
      b = binding
      b.local_variable_set(:x, 10)
      b.local_variable_set(:xy, 20)
      engine = described_class.new(b)
      # Only 'x' is referenced as a whole word, not 'xy'
      result = engine.execute("x + 1")
      expect(result).to eq(11)
      expect { described_class.context.eval("xy") }.to raise_error(MiniRacer::RuntimeError)
    end
  end

  describe "remote references (complex objects)" do
    before do
      Mana::ObjectRegistry.reset!
    end

    after do
      Mana::ObjectRegistry.reset!
    end

    it "passes complex objects as JS proxies" do
      klass = Class.new do
        attr_reader :value
        def initialize(v) @value = v; end
        def double() @value * 2; end
      end

      obj = klass.new(21)
      b = binding
      engine = described_class.new(b)
      result = engine.execute("obj.double()")
      expect(result).to eq(42)
    end

    it "allows calling methods with arguments on proxied objects" do
      klass = Class.new do
        def add(a, b) a + b; end
      end

      calc = klass.new
      b = binding
      engine = described_class.new(b)
      result = engine.execute("calc.add(3, 4)")
      expect(result).to eq(7)
    end

    it "registers complex objects in the ObjectRegistry" do
      obj = Object.new
      b = binding
      engine = described_class.new(b)
      engine.execute("obj.toString()")
      expect(Mana::ObjectRegistry.current.size).to be >= 1
    end

    it "can check if a proxy is alive" do
      obj = Object.new
      b = binding
      engine = described_class.new(b)
      result = engine.execute("obj.__mana_alive")
      expect(result).to be true
    end

    it "can release a proxy" do
      obj = Object.new
      b = binding
      engine = described_class.new(b)
      ref_id = engine.execute("obj.__mana_ref")
      engine.execute("obj.release()")
      expect(Mana::ObjectRegistry.current.registered?(ref_id)).to be false
    end

    it "can get the type name of a proxy" do
      obj = [1, 2, 3] # Use a known class, not anonymous
      # But Array is simple type... use a Struct
      MyStruct = Struct.new(:x) unless defined?(MyStruct)
      obj = MyStruct.new(42)
      b = binding
      engine = described_class.new(b)
      result = engine.execute("obj.__mana_type")
      expect(result).to be_a(String)
      expect(result).to include("MyStruct")
    end

    it "still passes simple types by value (not proxy)" do
      num = 42
      str = "hello"
      arr = [1, 2, 3]
      hash = { "a" => 1 }
      b = binding
      engine = described_class.new(b)

      # These should work as regular JS values, not proxies
      expect(engine.execute("num + 1")).to eq(43)
      expect(engine.execute("str + '!'")).to eq("hello!")
      expect(engine.execute("arr.length")).to eq(3)
      expect(engine.execute("hash.a")).to eq(1)
    end

    it "proxied object method results are JSON-safe" do
      klass = Class.new do
        def data() { "x" => 1, "y" => [2, 3] }; end
      end

      obj = klass.new
      b = binding
      engine = described_class.new(b)
      engine.execute("const d = obj.data()")
      expect(b.local_variable_get(:d)).to eq({ "x" => 1, "y" => [2, 3] })
    end

    it "handles multiple proxied objects" do
      klass = Class.new do
        attr_reader :name
        def initialize(n) @name = n; end
      end

      a = klass.new("Alice")
      b_obj = klass.new("Bob")
      b = binding
      engine = described_class.new(b)
      engine.execute("const names = a.name() + ' and ' + b_obj.name()")
      expect(b.local_variable_get(:names)).to eq("Alice and Bob")
    end

    it "does not allow calling private methods on proxied objects" do
      klass = Class.new do
        def greet() "hello"; end
        private
        def secret_method() "secret"; end
      end

      obj = klass.new
      b = binding
      engine = described_class.new(b)
      expect(engine.execute("obj.greet()")).to eq("hello")
      expect { engine.execute("obj.secret_method()") }.to raise_error(NoMethodError, /private/)
    end
  end
end
