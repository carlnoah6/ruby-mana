# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Backends::Base do
  describe "#chat" do
    it "raises NotImplementedError" do
      config = Mana::Config.new.tap { |c| c.api_key = "test-key" }
      backend = described_class.new(config)
      expect {
        backend.chat(system: "sys", messages: [], tools: [], model: "test")
      }.to raise_error(NotImplementedError, /chat not implemented/)
    end
  end

  describe "#http_post (via Anthropic subclass)" do
    let(:config) do
      Mana::Config.new.tap do |c|
        c.api_key = "test-key"
        c.base_url = "https://api.anthropic.com"
        c.model = "claude-sonnet-4-20250514"
      end
    end
    let(:backend) { Mana::Backends::Anthropic.new(config) }
    let(:tools) { [{ name: "done", description: "done", input_schema: { type: "object", properties: {} } }] }

    it "wraps Net::OpenTimeout in LLMError" do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:request).and_raise(Net::OpenTimeout.new("connection timed out"))

      expect {
        backend.chat(system: "sys", messages: [], tools: tools, model: "claude-sonnet-4-20250514")
      }.to raise_error(Mana::LLMError, /timed out/)
    end

    it "wraps Net::ReadTimeout in LLMError" do
      stub_request(:post, "https://api.anthropic.com/v1/messages").to_timeout

      expect {
        backend.chat(system: "sys", messages: [], tools: tools, model: "claude-sonnet-4-20250514")
      }.to raise_error(Mana::LLMError, /timed out/)
    end

    it "raises LLMError on non-success HTTP status" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 400, body: "Bad Request")

      expect {
        backend.chat(system: "sys", messages: [], tools: tools, model: "claude-sonnet-4-20250514")
      }.to raise_error(Mana::LLMError, /HTTP 400/)
    end

    it "includes response body in error message" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 401, body: '{"error":"invalid_api_key"}')

      expect {
        backend.chat(system: "sys", messages: [], tools: tools, model: "claude-sonnet-4-20250514")
      }.to raise_error(Mana::LLMError, /invalid_api_key/)
    end

    it "sets SSL when using https" do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:request).and_return(
        instance_double(Net::HTTPSuccess, is_a?: true, code: "200", body: JSON.generate({ content: [] }))
      )

      backend.chat(system: "sys", messages: [], tools: tools, model: "claude-sonnet-4-20250514")
      expect(http_double).to have_received(:use_ssl=).with(true)
    end

    it "disables SSL for http URLs" do
      config.base_url = "http://localhost:11434"
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:request).and_return(
        instance_double(Net::HTTPSuccess, is_a?: true, code: "200", body: JSON.generate({ content: [] }))
      )

      backend.chat(system: "sys", messages: [], tools: tools, model: "claude-sonnet-4-20250514")
      expect(http_double).to have_received(:use_ssl=).with(false)
    end
  end

  describe "#http_post_stream (via Anthropic#chat_stream)" do
    let(:config) do
      Mana::Config.new.tap do |c|
        c.api_key = "test-key"
        c.base_url = "https://api.anthropic.com"
        c.model = "claude-sonnet-4-20250514"
        c.timeout = 30
      end
    end
    let(:backend) { Mana::Backends::Anthropic.new(config) }
    let(:tools) { [{ name: "done", description: "done", input_schema: { type: "object", properties: {} } }] }

    it "wraps SocketError in LLMError" do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:request).and_raise(SocketError.new("getaddrinfo: Name or service not known"))

      expect {
        backend.chat_stream(system: "sys", messages: [], tools: tools, model: "claude-sonnet-4-20250514")
      }.to raise_error(Mana::LLMError, /Connection failed/)
    end

    it "wraps Errno::ECONNREFUSED in LLMError" do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:request).and_raise(Errno::ECONNREFUSED.new("Connection refused"))

      expect {
        backend.chat_stream(system: "sys", messages: [], tools: tools, model: "claude-sonnet-4-20250514")
      }.to raise_error(Mana::LLMError, /Connection failed/)
    end

    it "wraps Errno::ECONNRESET in LLMError" do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:request).and_raise(Errno::ECONNRESET.new("Connection reset"))

      expect {
        backend.chat_stream(system: "sys", messages: [], tools: tools, model: "claude-sonnet-4-20250514")
      }.to raise_error(Mana::LLMError, /Connection failed/)
    end

    it "wraps Net::OpenTimeout in LLMError for streaming" do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:request).and_raise(Net::OpenTimeout.new("timed out"))

      expect {
        backend.chat_stream(system: "sys", messages: [], tools: tools, model: "claude-sonnet-4-20250514")
      }.to raise_error(Mana::LLMError, /timed out/)
    end

    it "wraps Net::ReadTimeout in LLMError for streaming" do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:request).and_raise(Net::ReadTimeout.new("read timed out"))

      expect {
        backend.chat_stream(system: "sys", messages: [], tools: tools, model: "claude-sonnet-4-20250514")
      }.to raise_error(Mana::LLMError, /timed out/)
    end

    it "raises LLMError on non-success HTTP status" do
      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)

      error_response = instance_double(Net::HTTPBadRequest, code: "400")
      allow(error_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(http_double).to receive(:request).and_yield(error_response)

      expect {
        backend.chat_stream(system: "sys", messages: [], tools: tools, model: "claude-sonnet-4-20250514")
      }.to raise_error(Mana::LLMError, /HTTP 400/)
    end
  end
end
