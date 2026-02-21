# frozen_string_literal: true

module Mana
  # Session maintains conversation context across multiple ~"..." calls.
  #
  # Usage:
  #   Mana.session do
  #     ~"remember: user prefers concise style"
  #     ~"translate <text>"      # remembers the preference
  #     ~"translate <text2>"     # still remembers
  #   end
  #
  # Without a session, each ~"..." starts fresh with no memory.
  class Session
    attr_reader :messages

    def initialize
      @messages = []
    end

    class << self
      # Get the current thread-local session (if any)
      def current
        Thread.current[:mana_session]
      end

      # Run a block within a session scope
      def run(&block)
        previous = Thread.current[:mana_session]
        session = new
        Thread.current[:mana_session] = session
        block.call(session)
      ensure
        Thread.current[:mana_session] = previous
      end
    end
  end
end
