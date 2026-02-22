# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::ObjectRegistry do
  let(:registry) { described_class.new }

  after do
    described_class.reset!
  end

  describe "#register" do
    it "assigns a unique integer ID" do
      obj = Object.new
      id = registry.register(obj)
      expect(id).to be_a(Integer)
      expect(id).to be > 0
    end

    it "returns the same ID for the same object" do
      obj = Object.new
      id1 = registry.register(obj)
      id2 = registry.register(obj)
      expect(id1).to eq(id2)
    end

    it "assigns different IDs for different objects" do
      obj1 = Object.new
      obj2 = Object.new
      id1 = registry.register(obj1)
      id2 = registry.register(obj2)
      expect(id1).not_to eq(id2)
    end

    it "uses identity (equal?) not equality (==)" do
      a = Object.new
      b = Object.new
      id1 = registry.register(a)
      id2 = registry.register(b)
      expect(id1).not_to eq(id2)
    end
  end

  describe "#get" do
    it "retrieves the registered object" do
      obj = Object.new
      id = registry.register(obj)
      expect(registry.get(id)).to equal(obj)
    end

    it "returns nil for unknown IDs" do
      expect(registry.get(999)).to be_nil
    end
  end

  describe "#release" do
    it "removes the reference" do
      obj = Object.new
      id = registry.register(obj)
      expect(registry.release(id)).to be true
      expect(registry.get(id)).to be_nil
    end

    it "returns false for unknown IDs" do
      expect(registry.release(999)).to be false
    end
  end

  describe "#size" do
    it "tracks the number of live references" do
      expect(registry.size).to eq(0)
      id1 = registry.register(Object.new)
      expect(registry.size).to eq(1)
      registry.register(Object.new)
      expect(registry.size).to eq(2)
      registry.release(id1)
      expect(registry.size).to eq(1)
    end
  end

  describe "#clear!" do
    it "removes all references" do
      3.times { registry.register(Object.new) }
      expect(registry.size).to eq(3)
      registry.clear!
      expect(registry.size).to eq(0)
    end
  end

  describe "#registered?" do
    it "returns true for registered IDs" do
      id = registry.register(Object.new)
      expect(registry.registered?(id)).to be true
    end

    it "returns false for released IDs" do
      id = registry.register(Object.new)
      registry.release(id)
      expect(registry.registered?(id)).to be false
    end
  end

  describe ".current" do
    it "returns a thread-local singleton" do
      reg1 = described_class.current
      reg2 = described_class.current
      expect(reg1).to equal(reg2)
    end

    it "is isolated per thread" do
      main_reg = described_class.current
      thread_reg = nil
      Thread.new { thread_reg = described_class.current }.join
      expect(main_reg).not_to equal(thread_reg)
    end
  end

  describe ".reset!" do
    it "clears the thread-local registry" do
      reg = described_class.current
      reg.register(Object.new)
      described_class.reset!
      expect(described_class.current).not_to equal(reg)
      expect(described_class.current.size).to eq(0)
    end
  end
end
