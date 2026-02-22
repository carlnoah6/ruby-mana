# frozen_string_literal: true

require "spec_helper"
require "mana/engines/javascript"

# Integration tests for cross-engine interoperability.
# Validates: capability flags, data flow between engines, LLM boundary,
# and RemoteRef + ObjectRegistry across engine boundaries.
RSpec.describe "Cross-engine interop" do
  before do
    Mana::Engines::JavaScript.reset!
    Mana::ObjectRegistry.reset!
    Mana.config.api_key = "test-key"
  end

  after do
    Mana::Engines::JavaScript.reset!
    Mana::ObjectRegistry.reset!
  end

  # ---------------------------------------------------------------
  # 1. Capability flags
  # ---------------------------------------------------------------
  describe "engine capability flags" do
    it "Ruby engine supports everything" do
      b = binding
      engine = Mana::Engines::Ruby.new(b)
      expect(engine.supports_remote_ref?).to be true
      expect(engine.supports_bidirectional?).to be true
      expect(engine.supports_state?).to be true
    end

    it "JavaScript engine supports everything" do
      b = binding
      engine = Mana::Engines::JavaScript.new(b)
      expect(engine.supports_remote_ref?).to be true
      expect(engine.supports_bidirectional?).to be true
      expect(engine.supports_state?).to be true
    end

    it "LLM engine explicitly has no remote ref, no bidirectional, no state" do
      b = binding
      engine = Mana::Engines::LLM.new(b)
      expect(engine.supports_remote_ref?).to be false
      expect(engine.supports_bidirectional?).to be false
      expect(engine.supports_state?).to be false
    end
  end

  # ---------------------------------------------------------------
  # 2. Ruby ↔ JS data flow
  # ---------------------------------------------------------------
  describe "Ruby ↔ JavaScript data flow" do
    it "passes simple types from Ruby to JS and back" do
      name = "Mana"
      count = 42
      flag = true
      b = binding
      js = Mana::Engines::JavaScript.new(b)
      js.execute("const greeting = name + ' v' + count")
      expect(b.local_variable_get(:greeting)).to eq("Mana v42")
    end

    it "passes arrays from Ruby to JS, transforms, and returns" do
      numbers = [10, 20, 30, 40, 50]
      b = binding
      js = Mana::Engines::JavaScript.new(b)
      js.execute("const doubled = numbers.map(n => n * 2)")
      expect(b.local_variable_get(:doubled)).to eq([20, 40, 60, 80, 100])
    end

    it "passes hashes from Ruby to JS as objects" do
      config = { "host" => "localhost", "port" => 3000 }
      b = binding
      js = Mana::Engines::JavaScript.new(b)
      result = js.execute("config.host + ':' + config.port")
      expect(result).to eq("localhost:3000")
    end

    it "round-trips data: Ruby → JS transform → Ruby" do
      items = [3, 1, 4, 1, 5, 9]
      b = binding
      js = Mana::Engines::JavaScript.new(b)
      js.execute("const sorted = [...items].sort((a, b) => a - b)")
      expect(b.local_variable_get(:sorted)).to eq([1, 1, 3, 4, 5, 9])
    end
  end

  # ---------------------------------------------------------------
  # 3. JS → Ruby bidirectional calls
  # ---------------------------------------------------------------
  describe "JS → Ruby bidirectional calls" do
    it "JS calls Ruby methods on the receiver" do
      klass = Class.new do
        def greet(name)
          "Hello, #{name}!"
        end
      end

      obj = klass.new
      b = obj.instance_eval { binding }
      js = Mana::Engines::JavaScript.new(b)
      result = js.execute("ruby.greet('World')")
      expect(result).to eq("Hello, World!")
    end

    it "JS reads and writes Ruby variables" do
      counter = 10
      b = binding
      js = Mana::Engines::JavaScript.new(b)
      js.execute("ruby.write('counter', ruby.read('counter') + 5)")
      expect(b.local_variable_get(:counter)).to eq(15)
    end
  end

  # ---------------------------------------------------------------
  # 4. RemoteRef across engine boundaries
  # ---------------------------------------------------------------
  describe "RemoteRef across engines" do
    it "complex Ruby object becomes a proxy in JS" do
      klass = Class.new do
        attr_reader :value
        def initialize(v) @value = v; end
        def triple() @value * 3; end
      end

      obj = klass.new(7)
      b = binding
      js = Mana::Engines::JavaScript.new(b)
      result = js.execute("obj.triple()")
      expect(result).to eq(21)
    end

    it "multiple proxied objects coexist" do
      klass = Class.new do
        attr_reader :n
        def initialize(n) @n = n; end
        def add(x) @n + x; end
      end

      a = klass.new(10)
      b_obj = klass.new(20)
      b = binding
      js = Mana::Engines::JavaScript.new(b)
      result = js.execute("a.add(5) + b_obj.add(3)")
      expect(result).to eq(38) # (10+5) + (20+3)
    end

    it "ObjectRegistry tracks all proxied objects" do
      klass = Class.new do
        def ping() "pong"; end
      end

      x = klass.new
      y = klass.new
      b = binding
      js = Mana::Engines::JavaScript.new(b)
      js.execute("x.ping(); y.ping()")
      expect(Mana::ObjectRegistry.current.size).to be >= 2
    end

    it "release via JS removes from ObjectRegistry" do
      klass = Class.new do
        def hello() "hi"; end
      end

      obj = klass.new
      b = binding
      js = Mana::Engines::JavaScript.new(b)
      expect(js.execute("obj.hello()")).to eq("hi")

      # Get the ref_id that was assigned
      ref_id = Mana::ObjectRegistry.current.objects.keys.first
      expect(Mana::ObjectRegistry.current.registered?(ref_id)).to be true

      # Release via JS proxy
      js.execute("obj.release()")
      expect(Mana::ObjectRegistry.current.registered?(ref_id)).to be false
    end
  end

  # ---------------------------------------------------------------
  # 5. LLM engine boundary — no remote refs, no callbacks
  # ---------------------------------------------------------------
  describe "LLM engine boundary" do
    it "LLM serialize falls back to .to_s for complex objects" do
      klass = Class.new do
        def to_s() "CustomObj"; end
      end

      b = binding
      engine = Mana::Engines::LLM.new(b)
      result = engine.serialize(klass.new)
      expect(result).to eq("CustomObj")
    end

    it "LLM serialize copies simple types" do
      b = binding
      engine = Mana::Engines::LLM.new(b)
      expect(engine.serialize(42)).to eq(42)
      expect(engine.serialize("hello")).to eq("hello")
      expect(engine.serialize(true)).to eq(true)
      expect(engine.serialize(nil)).to eq(nil)
      expect(engine.serialize([1, 2])).to eq([1, 2])
    end

    it "LLM can read/write vars via tool loop (mocked)" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "write_var", input: { "name" => "result", "value" => 99 } }],
        [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "ok" } }]
      )

      result = nil
      b = binding
      engine = Mana::Engines::LLM.new(b)
      engine.execute("set result to 99")
      expect(b.local_variable_get(:result)).to eq(99)
    end
  end

  # ---------------------------------------------------------------
  # 6. Cross-engine data pipeline
  # ---------------------------------------------------------------
  describe "cross-engine data pipeline" do
    it "Ruby creates data, JS transforms, Ruby consumes" do
      # Ruby creates data
      data = (1..5).to_a
      b = binding
      rb = Mana::Engines::Ruby.new(b)
      rb.execute("total = data.sum")
      expect(b.local_variable_get(:total)).to eq(15)

      # JS transforms
      js = Mana::Engines::JavaScript.new(b)
      js.execute("const squared = data.map(n => n * n)")
      expect(b.local_variable_get(:squared)).to eq([1, 4, 9, 16, 25])
    end

    it "JS result feeds into Ruby eval engine" do
      b = binding
      js = Mana::Engines::JavaScript.new(b)
      js.execute("const items = ['a', 'b', 'c']")

      rb = Mana::Engines::Ruby.new(b)
      result = rb.execute("items.map(&:upcase)")
      expect(result).to eq(["A", "B", "C"])
    end
  end

  # ---------------------------------------------------------------
  # 7. Engine state persistence
  # ---------------------------------------------------------------
  describe "engine state persistence" do
    it "JS context persists variables via ruby.write bridge" do
      b = binding
      counter = 0
      js = Mana::Engines::JavaScript.new(b)
      # Use ruby.write to persist state back to Ruby binding
      js.execute("ruby.write('counter', 0)")
      js.execute("ruby.write('counter', ruby.read('counter') + 1)")
      js.execute("ruby.write('counter', ruby.read('counter') + 1)")
      expect(b.local_variable_get(:counter)).to eq(2)
    end

    it "Ruby eval shares the same binding across calls" do
      b = binding
      rb = Mana::Engines::Ruby.new(b)
      rb.execute("acc = 0")
      rb.execute("acc += 10")
      rb.execute("acc += 20")
      result = rb.execute("acc")
      expect(result).to eq(30)
    end
  end

  # ---------------------------------------------------------------
  # 8. ObjectRegistry isolation (thread safety)
  # ---------------------------------------------------------------
  describe "ObjectRegistry thread isolation" do
    it "registries are isolated per thread" do
      main_reg = Mana::ObjectRegistry.current
      main_reg.register(Object.new)

      thread_size = nil
      Thread.new do
        thread_size = Mana::ObjectRegistry.current.size
      end.join

      expect(main_reg.size).to be >= 1
      expect(thread_size).to eq(0)
    end
  end

  # ---------------------------------------------------------------
  # 9. GC: finalizer releases remote refs
  # ---------------------------------------------------------------
  describe "GC finalizer" do
    it "RemoteRef finalizer releases registry entry" do
      registry = Mana::ObjectRegistry.current
      obj = [1, 2, 3]
      id = registry.register(obj)

      ref = Mana::RemoteRef.new(id, source_engine: "test", registry: registry)
      expect(registry.registered?(id)).to be true

      # Explicit release simulates what GC finalizer does
      ref.release!
      expect(registry.registered?(id)).to be false
    end
  end
end
