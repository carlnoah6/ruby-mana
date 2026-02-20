# frozen_string_literal: true

require "webmock/rspec"
require "tempfile"
require "tmpdir"
require "mana"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.order = :random

  # Disable all external HTTP
  WebMock.disable_net_connect!
end

# Helper to stub Anthropic API responses
module AnthropicHelper
  def stub_anthropic_response(*tool_calls, text: nil)
    content = []

    tool_calls.each_with_index do |tc, i|
      content << {
        type: "tool_use",
        id: "toolu_#{i}",
        name: tc[:name],
        input: tc[:input] || {}
      }
    end

    content << { type: "text", text: text } if text

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate({ content: content })
      )
  end

  def stub_anthropic_done(result = nil)
    # First call: LLM does work, second call: LLM says done
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate({
          content: [{ type: "tool_use", id: "toolu_0", name: "done", input: { result: result } }]
        })
      )
  end

  def stub_anthropic_text_only(text = "OK")
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate({
          content: [{ type: "text", text: text }]
        })
      )
  end

  def stub_anthropic_sequence(*responses)
    stub = stub_request(:post, "https://api.anthropic.com/v1/messages")
    responses.each do |resp|
      stub = stub.to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate({ content: resp })
      )
    end
    stub
  end
end

RSpec.configure do |config|
  config.include AnthropicHelper
end
