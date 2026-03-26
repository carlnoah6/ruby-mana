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
      call_count = 0
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return do
          call_count += 1
          if call_count == 1
            # LLM writes the code to <code> variable
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t1", name: "write_var",
                  input: { "name" => "code", "value" => "def double(n)\n  n * 2\nend" } }]
              })
            }
          else
            # Then done
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t2", name: "done",
                  input: { "result" => "def double(n)\n  n * 2\nend" } }]
              })
            }
          end
        end

      klass = Class.new do
        include Mana::Mixin
        mana def double(n)
          ~"return n multiplied by 2"
        end
      end

      obj = klass.new
      expect(obj.double(5)).to eq(10)
    end

    it "preserves private visibility" do
      generated_code = "def secret(n)\n  n * 3\nend"
      allow(Mana::Compiler).to receive(:generate).and_return(generated_code)

      klass = Class.new do
        include Mana::Mixin
        private
        mana def secret(n)
          ~"return n tripled"
        end
      end

      obj = klass.new
      expect { obj.secret(5) }.to raise_error(NoMethodError, /private/)
      expect(obj.send(:secret, 5)).to eq(15)
    end

    it "works at top level (main object)" do
      # Top-level mana is defined in mixin.rb on Object's singleton class
      expect(TOPLEVEL_BINDING.eval("respond_to?(:mana)")).to be true
    end
  end
end
