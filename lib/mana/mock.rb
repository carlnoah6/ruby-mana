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

    # Initialize with an empty stub list
    def initialize
      @stubs = []
    end

    # Register a stub: when a prompt matches `pattern`, return `values` or call `block`
    def prompt(pattern, **values, &block)
      @stubs << Stub.new(pattern: pattern, values: values, block: block)
    end

    # Find the first stub that matches the given prompt text.
    # Regexp patterns use match?, String patterns use include?.
    def match(prompt_text)
      @stubs.find do |stub|
        case stub.pattern
        # Regex: full pattern match
        when Regexp then prompt_text.match?(stub.pattern)
        # String: substring match
        when String then prompt_text.include?(stub.pattern)
        end
      end
    end
  end

  class << self
    # Run a block with a mock active. Stubs defined inside are scoped to this block.
    # The block is instance_eval'd on the Mock so `prompt` is available as DSL.
    def mock(&block)
      old_mock = Thread.current[:mana_mock]
      m = Mock.new
      Thread.current[:mana_mock] = m
      m.instance_eval(&block)
    # Always restore the previous mock (supports nesting)
    ensure
      Thread.current[:mana_mock] = old_mock
    end

    # Enable mock mode (for use with before/after hooks in tests)
    def mock!
      Thread.current[:mana_mock] = Mock.new
    end

    # Disable mock mode and restore normal LLM calls
    def unmock!
      Thread.current[:mana_mock] = nil
    end

    # Check if mock mode is currently active on this thread
    def mock_active?
      !Thread.current[:mana_mock].nil?
    end

    # Returns the current thread's Mock instance, or nil if not in mock mode
    def current_mock
      Thread.current[:mana_mock]
    end
  end

  # RSpec helper — include in your test suite for automatic mock setup.
  #   RSpec.configure { |c| c.include Mana::TestHelpers }
  module TestHelpers
    # Auto-enable mock mode before each test, disable after
    def self.included(base)
      base.before { Mana.mock! }
      base.after { Mana.unmock! }
    end

    # Convenience method to register a stub within the current mock context
    def mock_prompt(pattern, **values, &block)
      raise Mana::MockError, "Mana mock mode not active. Call Mana.mock! first" unless Mana.mock_active?

      Mana.current_mock.prompt(pattern, **values, &block)
    end
  end
end
