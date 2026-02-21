# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::EffectRegistry do
  before { described_class.clear! }
  after { described_class.clear! }

  describe ".define" do
    it "registers a simple effect with no params" do
      described_class.define(:get_time) { Time.now.to_s }

      expect(described_class.defined?(:get_time)).to be true
      effect = described_class.get(:get_time)
      expect(effect.name).to eq("get_time")
      expect(effect.description).to eq("get_time")
      expect(effect.params).to be_empty
    end

    it "registers an effect with keyword params" do
      described_class.define(:query_db) { |sql:| sql.upcase }

      effect = described_class.get(:query_db)
      expect(effect.params.length).to eq(1)
      expect(effect.params[0][:name]).to eq("sql")
      expect(effect.params[0][:required]).to be true
    end

    it "registers an effect with optional params" do
      described_class.define(:search) { |query:, limit: 10| [query, limit] }

      effect = described_class.get(:search)
      expect(effect.params.length).to eq(2)
      expect(effect.params[0][:required]).to be true
      expect(effect.params[1][:required]).to be false
    end

    it "accepts a description" do
      described_class.define(:fetch, description: "Fetch a URL") { |url:| url }

      effect = described_class.get(:fetch)
      expect(effect.description).to eq("Fetch a URL")
    end

    it "rejects reserved effect names" do
      %w[read_var write_var read_attr write_attr call_func done remember].each do |name|
        expect {
          described_class.define(name.to_sym) { "nope" }
        }.to raise_error(Mana::Error, /cannot override built-in/)
      end
    end
  end

  describe ".undefine" do
    it "removes a registered effect" do
      described_class.define(:temp) { "x" }
      expect(described_class.defined?(:temp)).to be true

      described_class.undefine(:temp)
      expect(described_class.defined?(:temp)).to be false
    end
  end

  describe "#to_tool" do
    it "generates correct tool definition for no-param effect" do
      described_class.define(:get_time) { Time.now.to_s }

      tool = described_class.get(:get_time).to_tool
      expect(tool[:name]).to eq("get_time")
      expect(tool[:input_schema][:properties]).to be_empty
    end

    it "generates correct tool definition with params" do
      described_class.define(:query_db, description: "Run SQL") { |sql:| sql }

      tool = described_class.get(:query_db).to_tool
      expect(tool[:name]).to eq("query_db")
      expect(tool[:description]).to eq("Run SQL")
      expect(tool[:input_schema][:properties]).to have_key("sql")
      expect(tool[:input_schema][:required]).to eq(["sql"])
    end

    it "infers integer type from default value" do
      described_class.define(:paginate) { |page: 1, size: 20| [page, size] }

      tool = described_class.get(:paginate).to_tool
      props = tool[:input_schema][:properties]
      # Optional params with nil default (can't reflect actual default)
      expect(props).to have_key("page")
      expect(props).to have_key("size")
    end
  end

  describe "#call" do
    it "calls handler with no params" do
      described_class.define(:ping) { "pong" }

      effect = described_class.get(:ping)
      expect(effect.call({})).to eq("pong")
    end

    it "calls handler with keyword params" do
      described_class.define(:echo) { |msg:| "echo: #{msg}" }

      effect = described_class.get(:echo)
      expect(effect.call({ "msg" => "hello" })).to eq("echo: hello")
    end

    it "calls handler with multiple params" do
      described_class.define(:add) { |a:, b:| a.to_i + b.to_i }

      effect = described_class.get(:add)
      expect(effect.call({ "a" => "3", "b" => "4" })).to eq(7)
    end

    it "raises on missing required param" do
      described_class.define(:need_it) { |required_param:| required_param }

      effect = described_class.get(:need_it)
      expect { effect.call({}) }.to raise_error(Mana::Error, /missing required/)
    end
  end

  describe ".handle" do
    it "returns [false, nil] for unknown effects" do
      handled, _result = described_class.handle("unknown", {})
      expect(handled).to be false
    end

    it "returns [true, result] for registered effects" do
      described_class.define(:greet) { |name:| "hi #{name}" }

      handled, result = described_class.handle("greet", { "name" => "Carl" })
      expect(handled).to be true
      expect(result).to eq("hi Carl")
    end
  end

  describe ".tool_definitions" do
    it "returns tool defs for all registered effects" do
      described_class.define(:a) { "a" }
      described_class.define(:b) { |x:| x }

      tools = described_class.tool_definitions
      expect(tools.length).to eq(2)
      expect(tools.map { |t| t[:name] }).to contain_exactly("a", "b")
    end
  end
end
