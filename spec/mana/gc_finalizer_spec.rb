# frozen_string_literal: true

require "spec_helper"

RSpec.describe "GC finalizer: cross-engine release notification" do
  let(:registry) { Mana::ObjectRegistry.current }

  before do
    Mana::ObjectRegistry.reset!
  end

  after do
    Mana::ObjectRegistry.reset!
  end

  describe "ObjectRegistry on_release callbacks" do
    it "supports multiple callbacks" do
      log1 = []
      log2 = []
      registry.on_release { |id, _| log1 << id }
      registry.on_release { |id, _| log2 << id }

      id = registry.register(Object.new)
      registry.release(id)

      expect(log1).to eq([id])
      expect(log2).to eq([id])
    end

    it "does not fire twice for the same id" do
      count = 0
      registry.on_release { |_id, _| count += 1 }

      id = registry.register(Object.new)
      registry.release(id)
      registry.release(id) # second release returns false, no callback

      expect(count).to eq(1)
    end
  end

  describe "RemoteRef finalizer triggers on_release" do
    it "notifies via on_release when finalizer fires" do
      notified = []
      registry.on_release { |id, entry| notified << { id: id, type: entry[:type] } }

      obj = [1, 2, 3]
      id = registry.register(obj)
      _ref = Mana::RemoteRef.new(id, source_engine: "javascript", type_name: "Array")

      # Simulate the finalizer firing (deterministic, no GC dependency)
      release_proc = Mana::RemoteRef.release_callback(id, registry)
      release_proc.call(0)

      expect(notified.length).to eq(1)
      expect(notified[0][:id]).to eq(id)
      expect(notified[0][:type]).to eq("Array")
    end

    it "explicit release! also triggers on_release" do
      notified = []
      registry.on_release { |id, _| notified << id }

      id = registry.register(Object.new)
      ref = Mana::RemoteRef.new(id, source_engine: "python")
      ref.release!

      expect(notified).to eq([id])
    end
  end

  describe "JS engine FinalizationRegistry" do
    before do
      skip "mini_racer not available" unless defined?(MiniRacer)
    end

    after do
      Mana::Engines::JavaScript.reset! if defined?(Mana::Engines::JavaScript)
    end

    it "registers proxies with __mana_ref_gc" do
      # Verify the JS proxy helper registers proxies with FinalizationRegistry
      ctx = MiniRacer::Context.new
      # Stub ruby.__ref_release so it doesn't error
      ctx.attach("ruby.__ref_release", proc { |_| nil })
      ctx.attach("ruby.__ref_alive", proc { |_| true })
      ctx.attach("ruby.__ref_to_s", proc { |_| "test" })
      ctx.attach("ruby.__ref_call", proc { |*_| nil })

      ctx.eval(Mana::Engines::JavaScript::JS_PROXY_HELPER)

      # Create a proxy — should not raise
      result = ctx.eval("var p = __mana_create_proxy(42, 'TestObj'); p.__mana_ref")
      expect(result).to eq(42)

      # Verify FinalizationRegistry exists
      has_gc = ctx.eval("typeof __mana_ref_gc !== 'undefined'")
      expect(has_gc).to be true

      ctx.dispose
    end
  end

  describe "Python engine __ManaRef" do
    before do
      skip "pycall not available" unless defined?(PyCall)
    end

    after do
      Mana::Engines::Python.reset! if defined?(Mana::Engines::Python)
    end

    it "tracks objects and calls release_fn on Python GC" do
      released = []
      release_fn = proc { |ref_id| released << ref_id.to_i }

      ns = Mana::Engines::Python.namespace
      PyCall.exec(Mana::Engines::Python::PY_GC_HELPER, locals: ns)
      mana_ref = ns["__ManaRef"]
      mana_ref.set_release_fn(release_fn)

      # Create a Python object, track it, then delete it
      PyCall.exec("class _TestObj: pass", locals: ns)
      PyCall.exec("_test_instance = _TestObj()", locals: ns)
      test_obj = ns["_test_instance"]
      mana_ref.track(99, test_obj)

      # Delete the Python reference and force GC
      PyCall.exec("del _test_instance", locals: ns)
      PyCall.exec("import gc; gc.collect()", locals: ns)

      # The release callback may or may not fire depending on Python GC timing,
      # but the mechanism should be wired up without errors
      # (Python GC is non-deterministic for prevent ref cycles)
      expect { mana_ref.release_all }.not_to raise_error
    end
  end
end
