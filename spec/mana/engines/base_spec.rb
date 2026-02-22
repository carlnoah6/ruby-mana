# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Engines::Base do
  describe "#execute" do
    it "raises NotImplementedError" do
      engine = described_class.new(binding)
      expect { engine.execute("test") }.to raise_error(NotImplementedError, /execute not implemented/)
    end
  end

  describe "#read_var" do
    it "reads a local variable from the binding" do
      x = 42
      engine = described_class.new(binding)
      expect(engine.read_var("x")).to eq(42)
    end

    it "reads a method from the binding's receiver" do
      obj = Object.new
      def obj.my_method; "hello"; end
      b = obj.instance_eval { binding }
      engine = described_class.new(b)
      expect(engine.read_var("my_method")).to eq("hello")
    end

    it "raises NameError for undefined variables" do
      engine = described_class.new(binding)
      expect { engine.read_var("nonexistent") }.to raise_error(NameError)
    end
  end

  describe "#write_var" do
    it "sets a local variable in the binding" do
      b = binding
      engine = described_class.new(b)
      engine.write_var("new_var", 99)
      expect(b.local_variable_get(:new_var)).to eq(99)
    end

    it "overwrites an existing local variable" do
      existing = 10
      b = binding
      engine = described_class.new(b)
      engine.write_var("existing", 20)
      expect(b.local_variable_get(:existing)).to eq(20)
    end
  end

  describe "capability queries" do
    let(:engine) { described_class.new(binding) }

    it "defaults to supporting remote refs" do
      expect(engine.supports_remote_ref?).to be true
    end

    it "defaults to supporting bidirectional calls" do
      expect(engine.supports_bidirectional?).to be true
    end

    it "defaults to supporting state" do
      expect(engine.supports_state?).to be true
    end
  end

  describe "#serialize" do
    let(:engine) { described_class.new(binding) }

    it "passes through simple types" do
      expect(engine.serialize(42)).to eq(42)
      expect(engine.serialize("hello")).to eq("hello")
      expect(engine.serialize(:sym)).to eq(:sym)
      expect(engine.serialize(true)).to eq(true)
      expect(engine.serialize(nil)).to eq(nil)
      expect(engine.serialize(3.14)).to eq(3.14)
    end

    it "recursively serializes arrays" do
      expect(engine.serialize([1, "two", 3])).to eq([1, "two", 3])
    end

    it "recursively serializes hash values" do
      expect(engine.serialize({ a: 1, b: "two" })).to eq({ a: 1, b: "two" })
    end

    it "converts complex objects to strings" do
      obj = Object.new
      expect(engine.serialize(obj)).to be_a(String)
    end
  end
end
