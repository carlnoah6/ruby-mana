# frozen_string_literal: true

module Mana
  # Assembles system prompts and extracts variable context from user prompts.
  # Mixed into Engine as private methods.
  module PromptBuilder
    private

    # Extract <var> references from the prompt and read their current values.
    # Variables that don't exist yet are silently skipped (LLM will create them).
    def build_context(prompt)
      var_names = prompt.scan(/<(\w+)>/).flatten.uniq
      ctx = {}
      var_names.each do |name|
        val = resolve(name)
        ctx[name] = serialize_value(val)
      rescue NameError
        # Variable doesn't exist yet — will be created by LLM
      end
      ctx
    end

    # Assemble the system prompt with rules, memory, variables, available functions, and custom effects
    def build_system_prompt(context)
      parts = [
        "You are Mana, an AI assistant embedded in a Ruby program. Your name is Mana — never use any other name for yourself.",
        "ALWAYS respond in the same language as the user's message. If the user writes in Chinese, respond in Chinese. If in English, respond in English.",
        "You interact with live Ruby state using the provided tools. When unsure about your capabilities, use the knowledge tool to check.",
        "",
        "Rules:",
        "- read_var / read_attr to read, write_var / write_attr to write.",
        "- call_func to call ANY Ruby method — including Net::HTTP, File, system libraries, gems, etc. You have Ruby's full power. Use local_variables to discover variables in scope.",
        "- NEVER refuse a task by saying you can't do it. Always try using call_func first. If it fails, the error will tell you why.",
        "- done(result: ...) to return a value. error(message: ...) only after you have tried and failed.",
        "- <var> references point to variables in scope; create with write_var if missing.",
        "- Match types precisely: numbers for numeric values, arrays for lists, strings for text.",
        "- eval to define new methods, new classes, or require libraries. For operating on existing variables and functions, use read_var/write_var/call_func.",
        "- Current prompt overrides conversation history and memories.",
      ]

      mana_ctx = Context.current
      # Inject context when available
      if mana_ctx
        # Add compaction summaries from prior conversations
        unless mana_ctx.summaries.empty?
          parts << ""
          parts << "Previous conversation summary:"
          mana_ctx.summaries.each { |s| parts << "  #{s}" }
        end
      end

      # Inject registered prompt sections (e.g. long-term memories from claw)
      Mana.prompt_sections.each do |section_block|
        text = section_block.call
        parts << "" << text if text && !text.empty?
      end

      # Inject current variable values referenced in the prompt
      unless context.empty?
        parts << ""
        parts << "Current variable values:"
        context.each { |k, v| parts << "  #{k} = #{v}" }
      end

      # Discover available functions from two sources:
      # 1. AST scan of the caller's source file (gets parameter signatures)
      # 2. Receiver's methods minus Ruby builtins (catches require'd functions)
      file_methods = begin
        Mana::Introspect.methods_from_file(@caller_path)
      rescue => _e
        []
      end
      file_method_names = file_methods.map { |m| m[:name] }

      # Methods on the receiver not from Object/Kernel (user-defined or require'd)
      receiver = @binding.receiver
      receiver_methods = (receiver.methods - Object.methods - Kernel.methods - [:~@, :mana])
        .select { |m| receiver.method(m).owner != Object && receiver.method(m).owner != Kernel }
        .reject { |m| file_method_names.include?(m.to_s) }  # avoid duplicates with AST scan
        .map { |m|
          meth = receiver.method(m)
          params = meth.parameters.map { |(type, name)|
            case type
            when :req then name.to_s
            when :opt then "#{name}=..."
            when :rest then "*#{name}"
            when :keyreq then "#{name}:"
            when :key then "#{name}: ..."
            when :keyrest then "**#{name}"
            when :block then "&#{name}"
            else name.to_s
            end
          }
          { name: m.to_s, params: params }
        }

      all_methods = file_methods + receiver_methods
      # Append available function signatures so the LLM knows what it can call
      unless all_methods.empty?
        parts << ""
        parts << Mana::Introspect.format_for_prompt(all_methods)
      end

      # Inject Ruby runtime environment snapshot
      parts << ""
      parts << ruby_environment

      parts.join("\n")
    end

    # Build a concise snapshot of the Ruby runtime environment
    def ruby_environment
      lines = ["Environment:"]
      lines << "  Ruby #{RUBY_VERSION} | #{RUBY_PLATFORM} | pwd: #{Dir.pwd}"

      # Loaded gems (top-level, skip bundler internals)
      specs = Gem.loaded_specs.values
        .reject { |s| %w[bundler rubygems].include?(s.name) }
        .sort_by(&:name)
      if specs.any?
        gem_list = specs.map { |s| "#{s.name} #{s.version}" }.first(20)
        gem_list << "... (#{specs.size} total)" if specs.size > 20
        lines << "  Gems: #{gem_list.join(', ')}"
      end

      # User-defined classes/modules (skip Ruby internals)
      skip = [Object, Kernel, BasicObject, Module, Class, Mana, Mana::Engine,
              Mana::Memory, Mana::Context, Mana::Config]
      user_classes = ObjectSpace.each_object(Class)
        .reject { |c| c.name.nil? || c.name.start_with?("Mana::") || c.name.start_with?("#<") }
        .reject { |c| skip.include?(c) }
        .reject { |c| c.name.match?(/\A(Net|URI|IO|Gem|Bundler|RubyVM|RbConfig|Reline|JSON|YAML|Psych|Prism|Encoding|Errno|Signal|Thread|Fiber|Ractor|Process|GC|RDoc|IRB|Readline|StringIO|Monitor|PP|DidYouMean|ErrorHighlight|SyntaxSuggest|Coverage|SimpleCov|RSpec|WebMock)/) }
        .map(&:name).sort
      if user_classes.any?
        class_list = user_classes.first(20)
        class_list << "... (#{user_classes.size} total)" if user_classes.size > 20
        lines << "  Classes: #{class_list.join(', ')}"
      end

      # Local variables in scope
      vars = @binding.local_variables.map(&:to_s).sort
      lines << "  Local vars: #{vars.join(', ')}" if vars.any?

      lines.join("\n")
    end
  end
end
