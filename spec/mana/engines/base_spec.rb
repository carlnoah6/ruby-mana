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

end
