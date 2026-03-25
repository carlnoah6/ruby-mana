# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Engine do
  before do
    Mana.config.api_key = "test-key"
    Thread.current[:mana_memory] = nil
    Thread.current[:mana_incognito] = nil
    @tmpdir = Dir.mktmpdir("mana_test")
    Mana.config.memory_store = Mana::FileStore.new(@tmpdir)
  end

  after do
    Thread.current[:mana_memory] = nil
    Thread.current[:mana_incognito] = nil
    FileUtils.rm_rf(@tmpdir)
    Mana.reset!
  end

  describe ".run" do
    it "handles write_var to create new variables" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "write_var", input: { "name" => "result", "value" => 3.0 } }],
        [{ type: "tool_use", id: "t2", name: "done", input: {} }]
      )

      b = binding
      Mana::Engine.run("compute average and store in <result>", b)
      expect(b.local_variable_get(:result)).to eq(3.0)
    end

    it "handles read_var for existing variables" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "read_var", input: { "name" => "numbers" } }],
        [{ type: "tool_use", id: "t2", name: "write_var", input: { "name" => "total", "value" => 6 } }],
        [{ type: "tool_use", id: "t3", name: "done", input: {} }]
      )

      numbers = [1, 2, 3] # rubocop:disable Lint/UselessAssignment
      b = binding
      Mana::Engine.run("sum <numbers> into <total>", b)
      expect(b.local_variable_get(:total)).to eq(6)
    end

    it "handles read_attr and write_attr on objects" do
      klass = Struct.new(:name, :category, keyword_init: true)
      obj = klass.new(name: "test", category: nil)

      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "read_attr", input: { "obj" => "item", "attr" => "name" } }],
        [{ type: "tool_use", id: "t2", name: "write_attr", input: { "obj" => "item", "attr" => "category", "value" => "urgent" } }],
        [{ type: "tool_use", id: "t3", name: "done", input: {} }]
      )

      item = obj # rubocop:disable Lint/UselessAssignment
      b = binding
      Mana::Engine.run("read <item> name and set category", b)
      expect(obj.category).to eq("urgent")
    end

    it "handles call_func" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "double", "args" => [21] } }],
        [{ type: "tool_use", id: "t2", name: "write_var", input: { "name" => "result", "value" => 42 } }],
        [{ type: "tool_use", id: "t3", name: "done", input: {} }]
      )

      def double(n) = n * 2 # rubocop:disable Lint/UselessMethodDefinition

      b = binding
      Mana::Engine.run("call double(21) and store in <result>", b)
      expect(b.local_variable_get(:result)).to eq(42)
    end

    it "stops when LLM returns no tool calls" do
      stub_anthropic_text_only("All done!")

      b = binding
      expect { Mana::Engine.run("just say hi", b) }.not_to raise_error
    end

    it "raises on max iterations exceeded" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            content: [{ type: "tool_use", id: "t1", name: "read_var", input: { "name" => "x" } }]
          })
        )

      orig = Mana.config.max_iterations
      begin
        Mana.config.max_iterations = 3
        x = 1 # rubocop:disable Lint/UselessAssignment
        b = binding
        expect { Mana::Engine.run("loop forever on <x>", b) }.to raise_error(Mana::MaxIterationsError)
      ensure
        Mana.config.max_iterations = orig
      end
    end

    it "raises on HTTP error" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 500, body: "Internal Server Error")

      b = binding
      expect { Mana::Engine.run("fail", b) }.to raise_error(Mana::LLMError, /HTTP 500/)
    end

    it "returns done result" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "done", input: { "result" => "finished" } }]
      )

      b = binding
      result = Mana::Engine.run("do something", b)
      expect(result).to eq("finished")
    end

    it "rejects invalid variable names in write_var" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "write_var", input: { "name" => "system('rm -rf /')", "value" => 1 } }],
        [{ type: "tool_use", id: "t2", name: "done", input: {} }]
      )

      b = binding
      expect { Mana::Engine.run("try injection", b) }.not_to raise_error
    end

    it "rejects invalid function names in call_func" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "eval('bad')", "args" => [] } }],
        [{ type: "tool_use", id: "t2", name: "done", input: {} }]
      )

      b = binding
      expect { Mana::Engine.run("try injection", b) }.not_to raise_error
    end

    it "rejects invalid attr names in read_attr" do
      klass = Struct.new(:name, keyword_init: true)
      obj = klass.new(name: "test")

      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "read_attr", input: { "obj" => "item", "attr" => "send('exit')" } }],
        [{ type: "tool_use", id: "t2", name: "done", input: {} }]
      )

      item = obj # rubocop:disable Lint/UselessAssignment
      b = binding
      expect { Mana::Engine.run("try injection", b) }.not_to raise_error
    end

    it "handles multiple tool calls in one response" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            content: [
              { type: "tool_use", id: "t1", name: "write_var", input: { "name" => "xx", "value" => 1 } },
              { type: "tool_use", id: "t2", name: "write_var", input: { "name" => "yy", "value" => 2 } }
            ]
          })
        ).then
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            content: [{ type: "tool_use", id: "t3", name: "done", input: {} }]
          })
        )

      bnd = binding
      Mana::Engine.run("set xx=1 and yy=2", bnd)
      expect(bnd.local_variable_get(:xx)).to eq(1)
      expect(bnd.local_variable_get(:yy)).to eq(2)
    end

    it "handles unknown tool gracefully" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "nonexistent_tool", input: {} }],
        [{ type: "tool_use", id: "t2", name: "done", input: {} }]
      )

      b = binding
      expect { Mana::Engine.run("test", b) }.not_to raise_error
    end

    it "handles remember tool" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "remember", input: { "content" => "user likes Ruby" } }],
        [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "ok" } }]
      )

      b = binding
      Mana::Engine.run("remember I like Ruby", b)
      expect(Mana.memory.long_term.size).to eq(1)
      expect(Mana.memory.long_term.first[:content]).to eq("user likes Ruby")
    end

    it "blocks remember in incognito mode" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "remember", input: { "content" => "secret" } }],
        [{ type: "tool_use", id: "t2", name: "done", input: {} }]
      )

      Mana::Memory.incognito do
        b = binding
        Mana::Engine.run("remember this", b)
      end

      memory = Mana.memory
      expect(memory.long_term).to be_empty
    end
  end

  describe "#execute" do
    it "runs the tool-calling loop and returns written variable value" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "write_var", input: { "name" => "x", "value" => 42 } }],
        [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "ok" } }]
      )

      b = binding
      engine = described_class.new(b)
      result = engine.execute("set <x> to 42")
      expect(result).to eq(42)
      expect(b.local_variable_get(:x)).to eq(42)
    end
  end

  describe "#build_context" do
    it "reads existing variables referenced in prompt" do
      b = binding.tap { |b|
        b.local_variable_set(:x, 42)
        b.local_variable_set(:y, "hello")
      }
      engine = described_class.new(b)

      ctx = engine.send(:build_context, "use <x> and <y>")
      expect(ctx["x"]).to eq("42")
      expect(ctx["y"]).to eq('"hello"')
    end

    it "skips variables that don't exist yet" do
      b = binding
      engine = described_class.new(b)
      ctx = engine.send(:build_context, "store in <new_var>")
      expect(ctx).to be_empty
    end
  end

  describe "#serialize_value" do
    let(:engine) { described_class.new(binding) }

    it "serializes primitives" do
      expect(engine.send(:serialize_value, 42)).to eq("42")
      expect(engine.send(:serialize_value, 3.14)).to eq("3.14")
      expect(engine.send(:serialize_value, "hello")).to eq('"hello"')
      expect(engine.send(:serialize_value, true)).to eq("true")
      expect(engine.send(:serialize_value, nil)).to eq("nil")
    end

    it "serializes arrays" do
      expect(engine.send(:serialize_value, [1, "two", 3])).to eq('[1, "two", 3]')
    end

    it "serializes hashes" do
      result = engine.send(:serialize_value, { a: 1 })
      expect(result).to include('"a" => 1')
    end

    it "serializes custom objects via instance variables" do
      obj = Object.new
      obj.instance_variable_set(:@name, "Alice")
      obj.instance_variable_set(:@age, 30)
      result = engine.send(:serialize_value, obj)
      expect(result).to include("name")
      expect(result).to include("Alice")
    end

    it "serializes Time objects as readable strings" do
      result = engine.send(:serialize_value, Time.new(2026, 3, 23, 12, 0, 0, "+08:00"))
      expect(result).to include("2026-03-23")
      expect(result).to include("12:00:00")
    end
  end

  describe "call_func with dotted methods" do
    it "allows Class.method calls like Time.now" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "Time.now" } }],
        [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "ok" } }]
      )

      b = binding
      engine = described_class.new(b)
      result = engine.execute("get time")
      expect(result).to eq("ok")
    end

    it "allows chained calls like Time.now.to_s" do
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "Time.now.to_s" } }],
        [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "ok" } }]
      )

      b = binding
      engine = described_class.new(b)
      result = engine.execute("get time string")
      expect(result).to eq("ok")
    end

    it "blocks receiver calls per security policy" do
      Mana.config.security = :strict
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "File.read", "args" => ["/etc/hosts"] } }],
        [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "ok" } }]
      )

      b = binding
      engine = described_class.new(b)
      engine.execute("read file")
    end

    it "blocks methods per security policy" do
      Mana.config.security = :strict
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "eval" } }],
        [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "ok" } }]
      )

      b = binding
      engine = described_class.new(b)
      engine.execute("eval something")
    end
  end

  describe "verbose mode" do
    it "logs to stderr when verbose is true" do
      Mana.config.verbose = true
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "done", input: { "result" => "ok" } }]
      )

      b = binding
      engine = described_class.new(b)
      expect { engine.execute("test") }.to output(/LLM call/).to_stderr
      Mana.config.verbose = false
    end

    it "does not log when verbose is false" do
      Mana.config.verbose = false
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "done", input: { "result" => "ok" } }]
      )

      b = binding
      engine = described_class.new(b)
      expect { engine.execute("test") }.not_to output.to_stderr
    end
  end

  describe "#handle_mock" do
    it "matches and returns stubbed values" do
      b = binding
      Mana.mock do
        prompt "test", value: 42
        Mana::Engine.new(b).handle_mock("test prompt")
      end
      expect(b.local_variable_get(:value)).to eq(42)
    end
  end

  describe "custom effects integration" do
    before { Mana::EffectRegistry.clear! }
    after { Mana::EffectRegistry.clear! }

    it "dispatches to custom effect handler" do
      Mana.define_effect(:get_time) { "2026-02-20 12:00:00" }

      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "get_time", input: {} }],
        [{ type: "tool_use", id: "t2", name: "write_var", input: { "name" => "now", "value" => "2026-02-20 12:00:00" } }],
        [{ type: "tool_use", id: "t3", name: "done", input: {} }]
      )

      b = binding
      Mana::Engine.run("get the time and store in <now>", b)
      expect(b.local_variable_get(:now)).to eq("2026-02-20 12:00:00")
    end

    it "passes params to custom effect handler" do
      Mana.define_effect(:multiply) { |a:, b:| a.to_i * b.to_i }

      stub_anthropic_sequence(
        [{ type: "tool_use", id: "t1", name: "multiply", input: { "a" => 6, "b" => 7 } }],
        [{ type: "tool_use", id: "t2", name: "write_var", input: { "name" => "result", "value" => 42 } }],
        [{ type: "tool_use", id: "t3", name: "done", input: {} }]
      )

      b = binding
      Mana::Engine.run("multiply 6 and 7, store in <result>", b)
      expect(b.local_variable_get(:result)).to eq(42)
    end

    it "includes custom tools in all_tools" do
      Mana.define_effect(:custom_tool) { "ok" }

      tools = Mana::Engine.all_tools
      names = tools.map { |t| t[:name] }
      expect(names).to include("custom_tool")
      expect(names).to include("read_var")
      expect(names).to include("remember")
    end

    it "excludes remember tool in incognito mode" do
      Mana::Memory.incognito do
        tools = Mana::Engine.all_tools
        names = tools.map { |t| t[:name] }
        expect(names).not_to include("remember")
        expect(names).to include("read_var")
      end
    end
  end

  describe ".all_tools" do
    it "includes remember tool normally" do
      names = described_class.all_tools.map { |t| t[:name] }
      expect(names).to include("remember")
    end

    it "excludes remember tool in incognito" do
      Mana::Memory.incognito do
        names = described_class.all_tools.map { |t| t[:name] }
        expect(names).not_to include("remember")
      end
    end
  end
end
