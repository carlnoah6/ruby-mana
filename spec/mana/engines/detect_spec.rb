# frozen_string_literal: true

require "spec_helper"
require "mana/engines/javascript"

RSpec.describe Mana::Engines::Detector do
  let(:detector) { described_class.new }

  after do
    Mana::Engines.reset_detector!
  end

  describe "#detect" do
    context "JavaScript code" do
      it "detects const declarations" do
        result = detector.detect("const x = data.filter(n => n > 0)")
        expect(result).to eq(Mana::Engines::JavaScript)
      end

      it "detects let declarations" do
        result = detector.detect("let sum = arr.reduce((a, b) => a + b, 0)")
        expect(result).to eq(Mana::Engines::JavaScript)
      end

      it "detects arrow functions" do
        result = detector.detect("const fn = (x) => x * 2")
        expect(result).to eq(Mana::Engines::JavaScript)
      end

      it "detects console.log" do
        result = detector.detect('console.log("hello world")')
        expect(result).to eq(Mana::Engines::JavaScript)
      end

      it "detects async/await" do
        result = detector.detect("async function fetchData() { await fetch(url) }")
        expect(result).to eq(Mana::Engines::JavaScript)
      end

      it "detects === operator" do
        result = detector.detect("if (x === null) { return false }")
        expect(result).to eq(Mana::Engines::JavaScript)
      end
    end

    context "Python code" do
      it "detects list comprehension" do
        result = detector.detect("evens = [n for n in data if n % 2 == 0]")
        # Falls back to LLM since Python engine not implemented
        expect(result).to eq(Mana::Engines::LLM)
      end

      it "detects def keyword" do
        result = detector.detect("def calculate(x, y):\n    return x + y")
        expect(result).to eq(Mana::Engines::LLM) # Python falls back to LLM
      end

      it "detects Python-specific keywords" do
        result = detector.detect("print(self.__init__)")
        expect(result).to eq(Mana::Engines::LLM)
      end
    end

    context "Ruby code" do
      it "detects Ruby blocks with do |var|" do
        result = detector.detect("data.each do |item|\n  puts item\nend")
        expect(result).to eq(Mana::Engines::Ruby)
      end

      it "detects Ruby-specific keywords" do
        result = detector.detect("puts data.select { |n| n > 0 }")
        expect(result).to eq(Mana::Engines::Ruby)
      end

      it "detects attr_accessor with other Ruby signals" do
        result = detector.detect("class User\n  attr_accessor :name\nend")
        expect(result).to eq(Mana::Engines::Ruby)
      end
    end

    context "natural language" do
      it "detects natural language prompts" do
        result = detector.detect("analyze this data and find patterns")
        expect(result).to eq(Mana::Engines::LLM)
      end

      it "detects prompts with please" do
        result = detector.detect("please summarize the results")
        expect(result).to eq(Mana::Engines::LLM)
      end

      it "detects prompts with variable references" do
        result = detector.detect("store the result in <output>")
        expect(result).to eq(Mana::Engines::LLM)
      end
    end

    context "anti-patterns" do
      it "does not detect 'let me' as JavaScript" do
        result = detector.detect("let me think about this")
        expect(result).not_to eq(Mana::Engines::JavaScript)
      end

      it "does not detect 'let us' as JavaScript" do
        result = detector.detect("let us consider the options")
        expect(result).not_to eq(Mana::Engines::JavaScript)
      end

      it "does not detect 'const ant' as JavaScript" do
        result = detector.detect("the const ant buzzed around")
        expect(result).not_to eq(Mana::Engines::JavaScript)
      end

      it "does not detect 'for example' as Python" do
        result = detector.detect("for example, consider this case")
        expect(result).not_to eq(Mana::Engines::JavaScript)
      end
    end

    context "edge cases" do
      it "returns LLM for empty string" do
        result = detector.detect("")
        expect(result).to eq(Mana::Engines::LLM)
      end

      it "returns LLM for single word" do
        result = detector.detect("hello")
        expect(result).to eq(Mana::Engines::LLM)
      end

      it "returns LLM for whitespace" do
        result = detector.detect("   ")
        expect(result).to eq(Mana::Engines::LLM)
      end
    end

    context "context inference" do
      it "boosts previous language with context" do
        # First detect JS clearly
        result1 = detector.detect("const x = 1 + 2")
        expect(result1).to eq(Mana::Engines::JavaScript)

        # Ambiguous code with JS context should lean JS
        result2 = detector.detect("var y = x + 1", context: "javascript")
        expect(result2).to eq(Mana::Engines::JavaScript)
      end
    end
  end

  describe "determinism" do
    it "returns the same result for the same input" do
      code = "const x = data.filter(n => n > 0)"
      results = 10.times.map { detector.detect(code) }
      expect(results.uniq.size).to eq(1)
    end
  end
end

RSpec.describe Mana::Engines, ".detect" do
  after do
    Mana::Engines.reset_detector!
  end

  it "provides module-level convenience method" do
    result = Mana::Engines.detect("const x = 1 + 2")
    expect(result).to eq(Mana::Engines::JavaScript)
  end

  it "accepts context parameter" do
    result = Mana::Engines.detect("var y = 1", context: "javascript")
    expect(result).to eq(Mana::Engines::JavaScript)
  end
end
