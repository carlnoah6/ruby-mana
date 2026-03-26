# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Introspect do
  describe ".methods_from_file" do
    it "extracts simple method definitions" do
      file = create_temp_ruby(<<~RUBY)
        def greet(name)
          "Hello, \#{name}"
        end

        def add(a, b)
          a + b
        end
      RUBY

      methods = described_class.methods_from_file(file)
      expect(methods.length).to eq(2)
      expect(methods[0]).to include(name: "greet", params: ["name"])
      expect(methods[1]).to include(name: "add", params: %w[a b])
    end

    it "handles methods with no parameters" do
      file = create_temp_ruby(<<~RUBY)
        def hello
          "world"
        end
      RUBY

      methods = described_class.methods_from_file(file)
      expect(methods.first).to include(name: "hello", params: [])
    end

    it "handles optional parameters" do
      file = create_temp_ruby(<<~RUBY)
        def fetch(url, timeout = 30)
          # ...
        end
      RUBY

      methods = described_class.methods_from_file(file)
      expect(methods[0][:name]).to eq("fetch")
      expect(methods[0][:params]).to eq(["url", "timeout=..."])
    end

    it "handles keyword parameters" do
      file = create_temp_ruby(<<~RUBY)
        def search(query:, limit: 10)
          # ...
        end
      RUBY

      methods = described_class.methods_from_file(file)
      expect(methods[0][:params]).to eq(["query:", "limit: ..."])
    end

    it "handles splat and double splat" do
      file = create_temp_ruby(<<~RUBY)
        def log(*args, **opts)
          # ...
        end
      RUBY

      methods = described_class.methods_from_file(file)
      expect(methods[0][:params]).to eq(["*args", "**opts"])
    end

    it "handles block parameter" do
      file = create_temp_ruby(<<~RUBY)
        def each_item(&block)
          # ...
        end
      RUBY

      methods = described_class.methods_from_file(file)
      expect(methods[0][:params]).to eq(["&block"])
    end

    it "extracts methods inside class definitions" do
      file = create_temp_ruby(<<~RUBY)
        class Calculator
          def add(a, b)
            a + b
          end

          def multiply(a, b)
            a * b
          end
        end
      RUBY

      methods = described_class.methods_from_file(file)
      names = methods.map { |m| m[:name] }
      expect(names).to include("add", "multiply")
    end

    it "returns empty array for nil path" do
      expect(described_class.methods_from_file(nil)).to eq([])
    end

    it "returns empty array for nonexistent file" do
      expect(described_class.methods_from_file("/nonexistent/file.rb")).to eq([])
    end

    it "returns empty array for file with no methods" do
      file = create_temp_ruby(<<~RUBY)
        x = 1
        puts x + 2
      RUBY

      expect(described_class.methods_from_file(file)).to eq([])
    end
  end

  describe ".format_for_prompt" do
    it "formats methods with params" do
      methods = [
        { name: "search_db", params: ["query"] },
        { name: "calculate", params: ["expression"] }
      ]

      result = described_class.format_for_prompt(methods)
      expect(result).to include("Available Ruby functions:")
      expect(result).to include("search_db(query)")
      expect(result).to include("calculate(expression)")
    end

    it "formats methods without params" do
      methods = [{ name: "reset", params: [] }]
      result = described_class.format_for_prompt(methods)
      expect(result).to include("  reset")
      expect(result).not_to include("reset(")
    end

    it "returns empty string for empty list" do
      expect(described_class.format_for_prompt([])).to eq("")
    end
  end

  private

  def create_temp_ruby(source)
    file = Tempfile.new(["test", ".rb"])
    file.write(source)
    file.close
    file.path
  end

  describe "comment extraction" do
    it "extracts description from comments above def" do
      path = create_temp_ruby(<<~RUBY)
        # Calculate the sum of two numbers
        def add(a, b)
          a + b
        end
      RUBY

      methods = described_class.methods_from_file(path)
      expect(methods.first[:description]).to eq("Calculate the sum of two numbers")
    end

    it "extracts YARD @param types" do
      path = create_temp_ruby(<<~RUBY)
        # Query the database
        # @param sql [String] the SQL query
        # @param limit [Integer] max rows
        def query(sql:, limit: 10)
        end
      RUBY

      methods = described_class.methods_from_file(path)
      m = methods.first
      expect(m[:description]).to eq("Query the database")
      expect(m[:param_types]["sql"]).to eq("string")
      expect(m[:param_types]["limit"]).to eq("integer")
    end

    it "returns nil description when no comments" do
      path = create_temp_ruby(<<~RUBY)
        def bare_method(x)
          x
        end
      RUBY

      methods = described_class.methods_from_file(path)
      expect(methods.first[:description]).to be_nil
      expect(methods.first[:param_types]).to eq({})
    end

    it "skips @return tags" do
      path = create_temp_ruby(<<~RUBY)
        # Fetch a price
        # @param symbol [String] ticker
        # @return [Float] the price
        def fetch(symbol)
        end
      RUBY

      methods = described_class.methods_from_file(path)
      expect(methods.first[:description]).to eq("Fetch a price")
      expect(methods.first[:param_types]).to eq({ "symbol" => "string" })
    end

    it "includes description in format_for_prompt" do
      methods = [
        { name: "add", params: ["a", "b"], description: "Add two numbers", param_types: {} },
        { name: "sub", params: ["a", "b"], description: nil, param_types: {} }
      ]
      output = described_class.format_for_prompt(methods)
      expect(output).to include("add(a, b) — Add two numbers")
      expect(output).to include("  sub(a, b)")
      expect(output).not_to include("sub(a, b) —")
    end
  end
end
