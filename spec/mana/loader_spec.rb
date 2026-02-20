# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Loader do
  describe ".transform" do
    it "adds ~ before bare string statements" do
      source = <<~RUBY
        numbers = [1, 2, 3]
        "compute the average of <numbers> and store in <result>"
        puts result
      RUBY

      result = Mana::Loader.transform(source)
      expect(result).to include('~"compute the average')
      expect(result).to include("numbers = [1, 2, 3]")
      expect(result).to include("puts result")
    end

    it "does not modify assigned strings" do
      source = <<~RUBY
        html = "<div>hello</div>"
        name = "Alice"
      RUBY

      result = Mana::Loader.transform(source)
      expect(result).to eq(source)
    end

    it "does not modify strings passed as arguments" do
      source = <<~RUBY
        puts "hello world"
        render "<template>"
      RUBY

      result = Mana::Loader.transform(source)
      expect(result).to eq(source)
    end

    it "handles multiple bare strings" do
      source = <<~RUBY
        x = 1
        "do something with <x>"
        "do another thing"
        puts x
      RUBY

      result = Mana::Loader.transform(source)
      expect(result.scan("~\"").count).to eq(2)
    end

    it "handles bare strings inside method definitions" do
      source = <<~RUBY
        def process
          data = load
          "analyze <data> and store in <result>"
          save(result)
        end
      RUBY

      result = Mana::Loader.transform(source)
      expect(result).to include('~"analyze <data>')
    end

    it "handles bare strings inside blocks" do
      source = <<~RUBY
        items.each do |item|
          "process <item>"
        end
      RUBY

      result = Mana::Loader.transform(source)
      expect(result).to include('~"process <item>')
    end

    it "returns source unchanged when no bare strings" do
      source = <<~RUBY
        x = 1
        y = x + 2
        puts y
      RUBY

      result = Mana::Loader.transform(source)
      expect(result).to eq(source)
    end

    it "handles interpolated strings" do
      source = <<~'RUBY'
        name = "Alice"
        "say hello to #{name}"
      RUBY

      result = Mana::Loader.transform(source)
      expect(result).to include('~"say hello to')
    end
  end
end
