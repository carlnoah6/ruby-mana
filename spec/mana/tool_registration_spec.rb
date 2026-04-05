# frozen_string_literal: true

RSpec.describe "Mana tool registration" do
  include AnthropicHelper

  before do
    Mana.reset!
    Thread.current[:mana_memory] = nil
  end

  after do
    Mana.reset!
    Thread.current[:mana_memory] = nil
  end

  describe "Mana.register_tool" do
    it "adds a tool to registered_tools" do
      tool_def = { name: "my_tool", description: "test", input_schema: { type: "object", properties: {} } }
      Mana.register_tool(tool_def) { |input| "result" }

      expect(Mana.registered_tools).to include(tool_def)
    end

    it "registers the handler" do
      tool_def = { name: "my_tool", description: "test", input_schema: { type: "object", properties: {} } }
      Mana.register_tool(tool_def) { |input| "hello #{input['name']}" }

      handler = Mana.tool_handlers["my_tool"]
      expect(handler).not_to be_nil
      expect(handler.call({ "name" => "world" })).to eq("hello world")
    end
  end

  describe "Mana.clear_tools!" do
    it "clears all registered tools and handlers" do
      tool_def = { name: "my_tool", description: "test", input_schema: { type: "object", properties: {} } }
      Mana.register_tool(tool_def) { |input| "result" }

      Mana.clear_tools!

      expect(Mana.registered_tools).to be_empty
      expect(Mana.tool_handlers).to be_empty
    end
  end

  describe "Mana.reset!" do
    it "clears registered tools" do
      tool_def = { name: "my_tool", description: "test", input_schema: { type: "object", properties: {} } }
      Mana.register_tool(tool_def) { |input| "result" }

      Mana.reset!

      expect(Mana.registered_tools).to be_empty
    end
  end

  describe "Engine.all_tools" do
    it "includes registered tools" do
      tool_def = { name: "my_tool", description: "test", input_schema: { type: "object", properties: {} } }
      Mana.register_tool(tool_def) { |input| "result" }

      names = Mana::Engine.all_tools.map { |t| t[:name] }
      expect(names).to include("my_tool")
    end
  end

  describe "registered tool dispatch" do
    it "calls the registered handler during engine execution" do
      handler_called = false
      tool_def = {
        name: "custom_tool",
        description: "A custom tool",
        input_schema: {
          type: "object",
          properties: { msg: { type: "string" } },
          required: ["msg"]
        }
      }
      Mana.register_tool(tool_def) do |input|
        handler_called = true
        "custom result: #{input['msg']}"
      end

      Mana.configure { |c| c.api_key = "test-key" }

      # Stub: first call uses custom_tool, second call does done
      stub_anthropic_sequence(
        [{ type: "tool_use", id: "toolu_0", name: "custom_tool", input: { msg: "hello" } }],
        [{ type: "tool_use", id: "toolu_1", name: "done", input: { result: "ok" } }]
      )

      result = Mana::Engine.run("test", binding)
      expect(handler_called).to be true
      expect(result).to eq("ok")
    end
  end
end
