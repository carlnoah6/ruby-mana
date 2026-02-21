# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Backends::Anthropic do
  let(:config) do
    Mana::Config.new.tap do |c|
      c.api_key = "test-anthropic-key"
      c.base_url = "https://api.anthropic.com"
      c.model = "claude-sonnet-4-20250514"
    end
  end

  let(:backend) { described_class.new(config) }

  let(:tools) do
    [{ name: "done", description: "Signal done", input_schema: { type: "object", properties: {} } }]
  end

  describe "#chat" do
    it "sends correct auth headers" do
      stub = stub_request(:post, "https://api.anthropic.com/v1/messages")
        .with(
          headers: {
            "x-api-key" => "test-anthropic-key",
            "anthropic-version" => "2023-06-01",
            "Content-Type" => "application/json"
          }
        )
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ content: [{ type: "text", text: "hello" }] })
        )

      backend.chat(system: "sys", messages: [], tools: tools, model: "claude-sonnet-4-20250514")
      expect(stub).to have_been_requested
    end

    it "sends request body in Anthropic format" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .with { |req|
          body = JSON.parse(req.body)
          body["model"] == "claude-sonnet-4-20250514" &&
            body["max_tokens"] == 4096 &&
            body["system"] == "You are helpful." &&
            body["tools"].is_a?(Array) &&
            body["messages"] == [{ "role" => "user", "content" => "hi" }]
        }
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ content: [] })
        )

      backend.chat(
        system: "You are helpful.",
        messages: [{ role: "user", content: "hi" }],
        tools: tools,
        model: "claude-sonnet-4-20250514"
      )
    end

    it "returns content blocks from response" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            content: [
              { type: "text", text: "thinking..." },
              { type: "tool_use", id: "t1", name: "done", input: { result: "ok" } }
            ]
          })
        )

      result = backend.chat(system: "sys", messages: [], tools: tools, model: "claude-sonnet-4-20250514")
      expect(result.size).to eq(2)
      expect(result[0][:type]).to eq("text")
      expect(result[1][:type]).to eq("tool_use")
      expect(result[1][:name]).to eq("done")
    end

    it "returns empty array when content is nil" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({})
        )

      result = backend.chat(system: "sys", messages: [], tools: tools, model: "claude-sonnet-4-20250514")
      expect(result).to eq([])
    end

    it "raises LLMError on HTTP error" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 500, body: "Internal Server Error")

      expect {
        backend.chat(system: "sys", messages: [], tools: tools, model: "claude-sonnet-4-20250514")
      }.to raise_error(Mana::LLMError, /HTTP 500/)
    end

    it "uses custom base_url" do
      config.base_url = "https://custom-proxy.example.com"
      stub = stub_request(:post, "https://custom-proxy.example.com/v1/messages")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ content: [] })
        )

      backend.chat(system: "sys", messages: [], tools: tools, model: "claude-sonnet-4-20250514")
      expect(stub).to have_been_requested
    end
  end
end
