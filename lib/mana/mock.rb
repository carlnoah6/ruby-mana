# frozen_string_literal: true

module Mana
  # Test double for LLM calls. Stubs are matched against prompt text:
  #   Regexp patterns use match?, String patterns use include?.
  #
  # Usage:
  #   Mana.mock do
  #     prompt(/average/, result: 3.0)
  #     ~"compute average of <numbers> and store in <result>"
  #   end
  #
  # Thread-local — safe for parallel test execution.
  class Mock
    Stub = Struct.new(:pattern, :values, :block, keyword_init: true)

    attr_reader :stubs

    def initialize
      @stubs = []
    end

    def prompt(pattern, **values, &block)
      @stubs << Stub.new(pattern: pattern, values: values, block: block)
    end

    def match(prompt_text)
      @stubs.find do |stub|
        case stub.pattern
        when Regexp then prompt_text.match?(stub.pattern)
        when String then prompt_text.include?(stub.pattern)
        end
      end
    end
  end

  class << self
    def mock(&block)
      old_mock = Thread.current[:mana_mock]
      m = Mock.new
      Thread.current[:mana_mock] = m
      m.instance_eval(&block)
    ensure
      Thread.current[:mana_mock] = old_mock
    end

    def mock!
      Thread.current[:mana_mock] = Mock.new
    end

    def unmock!
      Thread.current[:mana_mock] = nil
    end

    def mock_active?
      !Thread.current[:mana_mock].nil?
    end

    def current_mock
      Thread.current[:mana_mock]
    end
  end
end
