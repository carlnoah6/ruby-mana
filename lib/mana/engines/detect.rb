# frozen_string_literal: true

require "yaml"

module Mana
  module Engines
    RULES_PATH = File.join(__dir__, "..", "..", "..", "data", "lang-rules.yml")

    class Detector
      attr_reader :rules

      def initialize(rules_path = RULES_PATH)
        @rules = YAML.safe_load(File.read(rules_path))["languages"]
      end

      # Detect language, return engine class
      # context: previous detection result (for context inference)
      def detect(code, context: nil)
        scores = {}
        @rules.each do |lang, rule_set|
          scores[lang] = score(code, rule_set)
        end

        # Context inference: boost previous language slightly
        # Only boost if there's already some evidence (score > 0)
        if context && scores[context] && scores[context] > 0
          scores[context] += 2
        end

        best = scores.max_by { |_, v| v }

        # If best score is very low, default to natural_language (LLM)
        if best[1] <= 0
          return engine_for("natural_language")
        end

        engine_for(best[0])
      end

      private

      def score(code, rule_set)
        s = 0
        # Strong signals: +3 each
        (rule_set["strong"] || []).each { |token| s += 3 if code.include?(token) }
        # Weak signals: +1 each
        (rule_set["weak"] || []).each { |token| s += 1 if code.include?(token) }
        # Anti signals: -5 each (strong negative)
        (rule_set["anti"] || []).each { |token| s -= 5 if code.include?(token) }
        # Pattern signals: +4 each
        (rule_set["patterns"] || []).each do |pattern|
          s += 4 if code.match?(Regexp.new(pattern))
        end
        s
      end

      def engine_for(lang)
        case lang
        when "javascript" then load_js_engine
        when "python" then load_py_engine
        when "ruby" then Engines::Ruby
        else Engines::LLM
        end
      end

      def load_js_engine
        require_relative "javascript"
        Engines::JavaScript
      rescue LoadError => e
        warn "Mana: JavaScript engine unavailable (#{e.message}), falling back to LLM"
        Engines::LLM
      end

      def load_py_engine
        warn "Mana: Python engine not yet available, falling back to LLM"
        Engines::LLM
      end
    end

    # Module-level convenience method
    def self.detect(code, context: nil)
      @detector ||= Detector.new
      @detector.detect(code, context: context)
    end

    def self.reset_detector!
      @detector = nil
    end
  end
end
