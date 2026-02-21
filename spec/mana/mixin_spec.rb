# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Mixin do
  before do
    Mana.config.api_key = "test-key"
    @tmpdir = Dir.mktmpdir("mana_test")
    Mana::Compiler.cache_dir = @tmpdir
  end

  after do
    FileUtils.rm_rf(@tmpdir)
    Mana.reset!
    Mana::Compiler.clear!
  end

  describe "included in a class" do
    it "makes mana available as a class method" do
      klass = Class.new do
        include Mana::Mixin
      end
      expect(klass).to respond_to(:mana)
    end
  end

  describe "mana def" do
    it "compiles a method via LLM and caches it" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            content: [
              { type: "tool_use", id: "t1", name: "done",
                input: { "result" => "def double(n)\n  n * 2\nend" } }
            ]
          })
        )

      klass = Class.new do
        include Mana::Mixin
        mana def double(n)
          ~"return n multiplied by 2"
        end
      end

      obj = klass.new
      expect(obj.double(5)).to eq(10)
    end
  end
end
