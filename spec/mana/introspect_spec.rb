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
      expect(methods[0]).to eq({ name: "greet", params: ["name"] })
      expect(methods[1]).to eq({ name: "add", params: %w[a b] })
    end

    it "handles methods with no parameters" do
      file = create_temp_ruby(<<~RUBY)
        def hello
          "world"
        end
      RUBY

      methods = described_class.methods_from_file(file)
      expect(methods).to eq([{ name: "hello", params: [] }])
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
end
