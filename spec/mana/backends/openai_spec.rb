# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Backends::OpenAI do
  let(:config) do
    Mana::Config.new.tap do |c|
      c.api_key = "test-openai-key"
      c.base_url = "https://api.openai.com"
      c.model = "gpt-4o"
    end
  end

  let(:backend) { described_class.new(config) }

  let(:tools) do
    [
      {
        name: "write_var",
        description: "Write a variable",
        input_schema: {
          type: "object",
          properties: { name: { type: "string" }, value: {} },
          required: %w[name value]
        }
      },
      {
        name: "done",
        description: "Signal done",
        input_schema: { type: "object", properties: { result: {} } }
      }
    ]
  end

  describe "#chat" do
    it "sends correct auth headers" do
      stub = stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .with(
          headers: {
            "Authorization" => "Bearer test-openai-key",
            "Content-Type" => "application/json"
          }
        )
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ choices: [{ message: { content: "hi" } }] })
        )

      backend.chat(system: "sys", messages: [], tools: tools, model: "gpt-4o")
      expect(stub).to have_been_requested
    end

    it "converts system prompt to system message" do
      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .with { |req|
          body = JSON.parse(req.body)
          body["messages"][0] == { "role" => "system", "content" => "You are helpful." }
        }
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ choices: [{ message: { content: "ok" } }] })
        )

      backend.chat(
        system: "You are helpful.",
        messages: [{ role: "user", content: "hi" }],
        tools: tools,
        model: "gpt-4o"
      )
    end

    it "converts tool definitions to OpenAI function format" do
      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .with { |req|
          body = JSON.parse(req.body)
          t = body["tools"][0]
          t["type"] == "function" &&
            t["function"]["name"] == "write_var" &&
            t["function"]["parameters"]["type"] == "object"
        }
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ choices: [{ message: { content: "ok" } }] })
        )

      backend.chat(system: "sys", messages: [], tools: tools, model: "gpt-4o")
    end

    it "converts tool_result messages to OpenAI tool role" do
      messages = [
        { role: "user", content: "do something" },
        {
          role: "assistant",
          content: [
            { type: "tool_use", id: "call_123", name: "write_var", input: { name: "x", value: 1 } }
          ]
        },
        {
          role: "user",
          content: [
            { type: "tool_result", tool_use_id: "call_123", content: "ok: x = 1" }
          ]
        }
      ]

      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .with { |req|
          body = JSON.parse(req.body)
          msgs = body["messages"]
          # system + user + assistant (with tool_calls) + tool
          msgs.length == 4 &&
            msgs[2]["role"] == "assistant" &&
            msgs[2]["tool_calls"][0]["function"]["name"] == "write_var" &&
            msgs[3]["role"] == "tool" &&
            msgs[3]["tool_call_id"] == "call_123"
        }
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ choices: [{ message: { content: "done" } }] })
        )

      backend.chat(system: "sys", messages: messages, tools: tools, model: "gpt-4o")
    end

    it "normalizes text response to Anthropic format" do
      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            choices: [{ message: { role: "assistant", content: "Hello!" } }]
          })
        )

      result = backend.chat(system: "sys", messages: [], tools: tools, model: "gpt-4o")
      expect(result).to eq([{ type: "text", text: "Hello!" }])
    end

    it "normalizes tool_calls response to Anthropic content blocks" do
      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            choices: [{
              message: {
                role: "assistant",
                content: nil,
                tool_calls: [
                  {
                    id: "call_abc",
                    type: "function",
                    function: {
                      name: "write_var",
                      arguments: '{"name":"result","value":42}'
                    }
                  }
                ]
              }
            }]
          })
        )

      result = backend.chat(system: "sys", messages: [], tools: tools, model: "gpt-4o")
      expect(result.size).to eq(1)
      expect(result[0][:type]).to eq("tool_use")
      expect(result[0][:id]).to eq("call_abc")
      expect(result[0][:name]).to eq("write_var")
      expect(result[0][:input]).to eq({ name: "result", value: 42 })
    end

    it "normalizes response with both text and tool_calls" do
      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            choices: [{
              message: {
                role: "assistant",
                content: "Let me help",
                tool_calls: [
                  {
                    id: "call_xyz",
                    type: "function",
                    function: { name: "done", arguments: '{"result":"ok"}' }
                  }
                ]
              }
            }]
          })
        )

      result = backend.chat(system: "sys", messages: [], tools: tools, model: "gpt-4o")
      expect(result.size).to eq(2)
      expect(result[0]).to eq({ type: "text", text: "Let me help" })
      expect(result[1][:type]).to eq("tool_use")
      expect(result[1][:name]).to eq("done")
    end

    it "returns empty array when no choices" do
      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ choices: [] })
        )

      result = backend.chat(system: "sys", messages: [], tools: tools, model: "gpt-4o")
      expect(result).to eq([])
    end

    it "raises LLMError on HTTP error" do
      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(status: 429, body: "Rate limited")

      expect {
        backend.chat(system: "sys", messages: [], tools: tools, model: "gpt-4o")
      }.to raise_error(Mana::LLMError, /HTTP 429/)
    end

    it "uses custom base_url for compatible APIs" do
      config.base_url = "http://localhost:11434"
      stub = stub_request(:post, "http://localhost:11434/v1/chat/completions")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ choices: [{ message: { content: "ok" } }] })
        )

      backend.chat(system: "sys", messages: [], tools: tools, model: "llama3")
      expect(stub).to have_been_requested
    end
  end
end
