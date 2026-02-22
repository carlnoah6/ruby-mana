# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::RemoteRef do
  let(:registry) { Mana::ObjectRegistry.current }

  before do
    Mana::ObjectRegistry.reset!
  end

  after do
    Mana::ObjectRegistry.reset!
  end

  describe "method proxying" do
    it "proxies method calls to the registered object" do
      obj = [1, 2, 3]
      id = registry.register(obj)
      ref = described_class.new(id, source_engine: "ruby", type_name: "Array")
      expect(ref.length).to eq(3)
      expect(ref.first).to eq(1)
    end

    it "proxies methods with arguments" do
      obj = [1, 2, 3, 4, 5]
      id = registry.register(obj)
      ref = described_class.new(id, source_engine: "ruby", type_name: "Array")
      expect(ref.select { |n| n > 3 }).to eq([4, 5])
    end

    it "raises when the reference has been released" do
      obj = Object.new
      id = registry.register(obj)
      ref = described_class.new(id, source_engine: "ruby", type_name: "Object")
      registry.release(id)
      expect { ref.length }.to raise_error(Mana::Error, /released/)
    end
  end

  describe "#alive?" do
    it "returns true when the object is still registered" do
      id = registry.register(Object.new)
      ref = described_class.new(id, source_engine: "ruby")
      expect(ref.alive?).to be true
    end

    it "returns false after release" do
      id = registry.register(Object.new)
      ref = described_class.new(id, source_engine: "ruby")
      ref.release!
      expect(ref.alive?).to be false
    end
  end

  describe "#release!" do
    it "removes the object from the registry" do
      id = registry.register(Object.new)
      ref = described_class.new(id, source_engine: "ruby")
      ref.release!
      expect(registry.registered?(id)).to be false
    end
  end

  describe "#inspect" do
    it "shows ref_id, engine, and type" do
      id = registry.register(Object.new)
      ref = described_class.new(id, source_engine: "javascript", type_name: "MyClass")
      expect(ref.inspect).to include("RemoteRef")
      expect(ref.inspect).to include("javascript")
      expect(ref.inspect).to include("MyClass")
    end
  end

  describe "#to_s" do
    it "delegates to the underlying object" do
      obj = "hello world"
      id = registry.register(obj)
      ref = described_class.new(id, source_engine: "ruby", type_name: "String")
      expect(ref.to_s).to eq("hello world")
    end
  end

  describe "respond_to_missing?" do
    it "returns true for methods the underlying object has" do
      obj = [1, 2, 3]
      id = registry.register(obj)
      ref = described_class.new(id, source_engine: "ruby")
      expect(ref.respond_to?(:length)).to be true
      expect(ref.respond_to?(:nonexistent_method)).to be false
    end
  end

  describe "GC finalizer" do
    it "has a finalizer that releases the registry entry" do
      obj = Object.new
      id = registry.register(obj)
      ref = described_class.new(id, source_engine: "ruby", type_name: "Object")

      # Simulate what the finalizer does (call the release_callback proc directly)
      release_proc = described_class.release_callback(id, registry)
      expect(registry.registered?(id)).to be true
      release_proc.call(0) # finalizer receives object_id, we pass dummy
      expect(registry.registered?(id)).to be false
    end

    it "fires on_release callbacks via the finalizer mechanism" do
      released_ids = []
      registry.on_release { |id, _entry| released_ids << id }

      obj = Object.new
      id = registry.register(obj)
      ref = described_class.new(id, source_engine: "ruby")

      # Simulate finalizer firing
      release_proc = described_class.release_callback(id, registry)
      release_proc.call(0)

      expect(released_ids).to eq([id])
    end

    it "registers a finalizer with ObjectSpace" do
      obj = Object.new
      id = registry.register(obj)

      # Verify define_finalizer is called
      expect(ObjectSpace).to receive(:define_finalizer).and_call_original
      described_class.new(id, source_engine: "ruby")
    end
  end

  describe "custom objects" do
    it "proxies methods on user-defined classes" do
      klass = Class.new do
        attr_reader :value
        def initialize(v)
          @value = v
        end

        def double
          @value * 2
        end
      end

      obj = klass.new(21)
      id = registry.register(obj)
      ref = described_class.new(id, source_engine: "javascript", type_name: klass.name)
      expect(ref.value).to eq(21)
      expect(ref.double).to eq(42)
    end
  end
end
