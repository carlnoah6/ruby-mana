# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Engines::Ruby do
  describe "#execute" do
    it "evaluates simple Ruby expressions" do
      b = binding
      engine = described_class.new(b)
      result = engine.execute("1 + 2")
      expect(result).to eq(3)
    end

    it "can set local variables in the binding" do
      b = binding
      engine = described_class.new(b)
      engine.execute("x = 42")
      expect(b.local_variable_get(:x)).to eq(42)
    end

    it "can read local variables from the binding" do
      data = [1, 2, 3]
      b = binding
      engine = described_class.new(b)
      result = engine.execute("data.sum")
      expect(result).to eq(6)
    end

    it "can call methods in the binding scope" do
      b = binding
      engine = described_class.new(b)
      result = engine.execute("[3, 1, 2].sort")
      expect(result).to eq([1, 2, 3])
    end

    it "returns the result of the last expression" do
      b = binding
      engine = described_class.new(b)
      result = engine.execute("a = 10\nb = 20\na + b")
      expect(result).to eq(30)
    end

    it "raises on invalid Ruby code" do
      b = binding
      engine = described_class.new(b)
      expect { engine.execute("def }{") }.to raise_error(SyntaxError)
    end
  end
end
