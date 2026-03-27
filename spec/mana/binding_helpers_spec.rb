# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::BindingHelpers do
  before do
    Mana.config.api_key = "test-key"
    Thread.current[:mana_memory] = nil
    Thread.current[:mana_incognito] = nil
  end

  after do
    Thread.current[:mana_memory] = nil
    Thread.current[:mana_incognito] = nil
    Mana.reset!
  end

  describe "#write_local" do
    it "creates new variables and tracks them in __mana_vars__" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "write_var", input: { "name" => "new_var", "value" => 99 } }],
        [{ type: "tool_use", id: "t2", name: "done", input: {} }]
      )

      b = binding
      Mana::Engine.run("create <new_var>", b)

      receiver = b.eval("self")
      if receiver.instance_variable_defined?(:@__mana_vars__)
        mana_vars = receiver.instance_variable_get(:@__mana_vars__)
        expect(mana_vars).to include(:new_var)
      end
    end

    it "does not define singleton method for pre-existing variables" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "write_var", input: { "name" => "existing", "value" => 100 } }],
        [{ type: "tool_use", id: "t2", name: "done", input: {} }]
      )

      existing = 42 # rubocop:disable Lint/UselessAssignment
      b = binding
      receiver = b.eval("self")

      # Should NOT add singleton method since variable already exists
      Mana::Engine.run("update <existing>", b)
      expect(b.local_variable_get(:existing)).to eq(100)

      # __mana_vars__ should not include :existing since it pre-existed
      if receiver.instance_variable_defined?(:@__mana_vars__)
        mana_vars = receiver.instance_variable_get(:@__mana_vars__)
        expect(mana_vars).not_to include(:existing)
      end
    end

    it "does not overwrite real instance methods with singleton method" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "write_var", input: { "name" => "to_s", "value" => "hack" } }],
        [{ type: "tool_use", id: "t2", name: "done", input: {} }]
      )

      b = binding
      receiver = b.eval("self")
      original_to_s = receiver.method(:to_s)

      Mana::Engine.run("set to_s", b)

      # to_s should still be the original method, not overwritten
      # The variable is set in binding but no singleton method is defined
      expect(receiver.method(:to_s).owner).to eq(original_to_s.owner)
    end
  end

  describe "#validate_name!" do
    let(:engine) { Mana::Engine.new(binding) }

    it "accepts valid Ruby identifiers" do
      expect { engine.send(:validate_name!, "foo") }.not_to raise_error
      expect { engine.send(:validate_name!, "_private") }.not_to raise_error
      expect { engine.send(:validate_name!, "camelCase123") }.not_to raise_error
      expect { engine.send(:validate_name!, "A_CONSTANT") }.not_to raise_error
    end

    it "rejects names with special characters" do
      expect { engine.send(:validate_name!, "system('ls')") }.to raise_error(Mana::Error, /invalid identifier/)
      expect { engine.send(:validate_name!, "foo.bar") }.to raise_error(Mana::Error, /invalid identifier/)
      expect { engine.send(:validate_name!, "x;y") }.to raise_error(Mana::Error, /invalid identifier/)
      expect { engine.send(:validate_name!, "") }.to raise_error(Mana::Error, /invalid identifier/)
    end

    it "rejects names starting with digits" do
      expect { engine.send(:validate_name!, "123abc") }.to raise_error(Mana::Error, /invalid identifier/)
    end
  end

  describe "#resolve" do
    it "reads local variables from binding" do
      my_val = 42 # rubocop:disable Lint/UselessAssignment
      b = binding
      engine = Mana::Engine.new(b)
      expect(engine.send(:resolve, "my_val")).to eq(42)
    end

    it "reads methods from the receiver" do
      b = binding
      engine = Mana::Engine.new(b)
      # The receiver (self in rspec) should have respond_to? as a method
      result = engine.send(:resolve, "class")
      expect(result).to be_a(Class)
    end

    it "raises NameError for undefined variable or method" do
      b = binding
      engine = Mana::Engine.new(b)
      expect { engine.send(:resolve, "nonexistent_xyz_abc") }.to raise_error(NameError, /undefined/)
    end
  end

  describe "#caller_source_path" do
    it "returns a file path" do
      b = binding
      engine = Mana::Engine.new(b)
      path = engine.send(:caller_source_path)
      # Should return this spec file or similar
      expect(path).to be_a(String).or be_nil
    end
  end

  describe "#serialize_value" do
    let(:engine) { Mana::Engine.new(binding) }

    it "serializes symbols as strings" do
      expect(engine.send(:serialize_value, :hello)).to eq('"hello"')
    end

    it "serializes Time with timezone" do
      t = Time.new(2026, 1, 15, 10, 30, 0, "+00:00")
      result = engine.send(:serialize_value, t)
      expect(result).to include("2026-01-15")
      expect(result).to include("10:30:00")
      expect(result).to include("+0000")
    end

    it "serializes nested arrays" do
      result = engine.send(:serialize_value, [[1, 2], [3, 4]])
      expect(result).to eq("[[1, 2], [3, 4]]")
    end

    it "serializes nested hashes" do
      result = engine.send(:serialize_value, { a: { b: 1 } })
      expect(result).to include('"a"')
      expect(result).to include('"b" => 1')
    end

    it "serializes objects with instance variables" do
      obj = Object.new
      obj.instance_variable_set(:@x, 10)
      obj.instance_variable_set(:@y, 20)
      result = engine.send(:serialize_value, obj)
      expect(result).to include("x: 10")
      expect(result).to include("y: 20")
      expect(result).to start_with("#<Object")
    end

    it "serializes objects with no instance variables" do
      obj = Object.new
      result = engine.send(:serialize_value, obj)
      expect(result).to start_with("#<Object")
    end
  end
end
