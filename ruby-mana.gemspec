# frozen_string_literal: true

require_relative "lib/mana/version"

Gem::Specification.new do |s|
  s.name        = "ruby-mana"
  s.version     = Mana::VERSION
  s.summary     = "Embed LLM as native Ruby — write natural language, it just runs"
  s.description = <<~DESC
    Mana lets you write natural language strings in Ruby that execute via LLM
    with full access to your program's live state. Read/write variables, call
    functions, manipulate objects — all from a simple ~"..." or bare strings
    in .nrb files.
  DESC
  s.authors     = ["Carl"]
  s.license     = "MIT"
  s.homepage    = "https://github.com/carlnoah6/ruby-mana"

  s.required_ruby_version = ">= 3.3.0"

  s.files = Dir["lib/**/*.rb"] + Dir["*.md"] + ["LICENSE"]
  s.require_paths = ["lib"]

  s.add_dependency "binding_of_caller", "~> 1.0"

  s.metadata = {
    "homepage_uri" => s.homepage,
    "source_code_uri" => s.homepage,
    "changelog_uri" => "#{s.homepage}/blob/main/CHANGELOG.md"
  }
end
