# frozen_string_literal: true

require_relative "mana/version"
require_relative "mana/config"
require_relative "mana/effects"
require_relative "mana/engine"
require_relative "mana/string_ext"
require_relative "mana/mixin"

module Mana
  class Error < StandardError; end
  class MaxIterationsError < Error; end
  class LLMError < Error; end

  class << self
    def config
      @config ||= Config.new
    end

    def configure
      yield(config) if block_given?
      config
    end

    def model=(model)
      config.model = model
    end

    def handle(handler = nil, **opts, &block)
      Engine.with_handler(handler, **opts, &block)
    end

    def reset!
      @config = Config.new
    end
  end
end
