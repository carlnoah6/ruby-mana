# frozen_string_literal: true

module Mana
  # Interactive chat mode — enter with Mana.chat to talk to Mana in your Ruby runtime.
  # Supports streaming output, colored prompts, and full access to the caller's binding.
  # Auto-detects Ruby code vs natural language. Use '!' prefix to force Ruby execution.
  module Chat
    USER_PROMPT  = "\e[36mmana>\e[0m "    # cyan
    MANA_PREFIX  = "\e[33mmana>\e[0m "   # yellow
    RUBY_PREFIX  = "\e[35m=>\e[0m "      # magenta
    THINK_COLOR  = "\e[3;36m"            # italic cyan
    TOOL_COLOR   = "\e[2;33m"            # dim yellow
    RESULT_COLOR = "\e[2;32m"            # dim green
    CODE_COLOR   = "\e[36m"              # cyan for code
    BOLD         = "\e[1m"               # bold
    ERROR_COLOR  = "\e[31m"              # red
    DIM          = "\e[2m"               # dim
    RESET        = "\e[0m"

    CONT_PROMPT  = "\e[2m  \e[0m"
    EXIT_COMMANDS = /\A(exit|quit|bye|q)\z/i

    # Entry point — starts the REPL loop with Reline for readline support.
    # Reline is required lazily so chat mode doesn't penalize non-interactive usage.
    HISTORY_FILE = File.join(Dir.home, ".mana_history")
    HISTORY_MAX  = 1000

    def self.start(caller_binding)
      require "reline"
      load_history
      puts "#{DIM}Mana chat · type 'exit' to quit#{RESET}"
      puts

      loop do
        input = read_input
        break if input.nil?
        next if input.strip.empty?
        break if input.strip.match?(EXIT_COMMANDS)

        # Three-tier dispatch:
        # "!" prefix — force Ruby eval (bypass ambiguity detection)
        # Valid Ruby syntax — try Ruby first, fall back to LLM if NameError
        # Everything else — send directly to the LLM
        if input.start_with?("!")
          eval_ruby(caller_binding, input[1..].strip)
        elsif ruby_syntax?(input)
          eval_ruby(caller_binding, input) { run_mana(caller_binding, input) }
        else
          run_mana(caller_binding, input)
        end
        puts
      end

      save_history
      puts "#{DIM}bye!#{RESET}"
    end

    def self.load_history
      return unless File.exist?(HISTORY_FILE)

      File.readlines(HISTORY_FILE, chomp: true).last(HISTORY_MAX).each do |line|
        Reline::HISTORY << line
      end
    rescue StandardError
      # ignore corrupt history
    end
    private_class_method :load_history

    def self.save_history
      lines = Reline::HISTORY.to_a.last(HISTORY_MAX)
      File.write(HISTORY_FILE, lines.join("\n") + "\n")
    rescue StandardError
      # ignore write failures
    end
    private_class_method :save_history

    # Reads input with multi-line support — keeps prompting with continuation
    # markers while the buffer contains incomplete Ruby (unclosed blocks, strings, etc.)
    def self.read_input
      # Second arg to readline: true = add to history, false = don't
      buffer = Reline.readline(USER_PROMPT, true)
      return nil if buffer.nil?

      while incomplete_ruby?(buffer)
        line = Reline.readline(CONT_PROMPT, false)
        break if line.nil?
        buffer += "\n" + line
      end
      buffer
    end
    private_class_method :read_input

    # Heuristic: if RubyVM can compile it, treat as Ruby code.
    # This lets users type `x = 1 + 2` without needing the "!" prefix.
    def self.ruby_syntax?(input)
      RubyVM::InstructionSequence.compile(input)
      true
    rescue SyntaxError
      false
    end
    private_class_method :ruby_syntax?

    # Distinguishes incomplete code (needs more input) from invalid code (syntax error).
    # Only "unexpected end-of-input" and "unterminated" indicate the user is still typing;
    # other SyntaxErrors mean the code is complete but malformed.
    def self.incomplete_ruby?(code)
      RubyVM::InstructionSequence.compile(code)
      false
    rescue SyntaxError => e
      e.message.include?("unexpected end-of-input") ||
        e.message.include?("unterminated")
    end
    private_class_method :incomplete_ruby?

    # Eval Ruby in the caller's binding. On NameError/NoMethodError, yields to the
    # fallback block (which sends to the LLM) — this is how ambiguous input like
    # "sort this list" gets routed: Ruby rejects it, then the LLM handles it.
    def self.eval_ruby(caller_binding, code)
      result = caller_binding.eval(code)
      puts "#{RUBY_PREFIX}#{result.inspect}"
    rescue NameError, NoMethodError => e
      block_given? ? yield : puts("#{ERROR_COLOR}#{e.class}: #{e.message}#{RESET}")
    rescue => e
      puts "#{ERROR_COLOR}#{e.class}: #{e.message}#{RESET}"
    end
    private_class_method :eval_ruby

    # --- Mana LLM execution with streaming + markdown rendering ---

    # Executes a prompt via the LLM engine with streaming output.
    # Uses a line buffer to render complete lines with markdown formatting
    # while the LLM streams tokens incrementally.
    def self.run_mana(caller_binding, input)
      streaming_text = false
      in_code_block = false
      line_buffer = +""       # mutable string — accumulates partial lines until \n
      engine = Engine.new(caller_binding)

      begin
        result = engine.execute(input) do |type, *args|
          case type
          when :text
            unless streaming_text
              print MANA_PREFIX
              streaming_text = true
            end

            # Buffer text and flush complete lines with markdown rendering
            line_buffer << args[0].to_s
            while (idx = line_buffer.index("\n"))
              line = line_buffer.slice!(0, idx + 1)
              in_code_block = render_line(line.chomp, in_code_block)
              puts
            end

          when :tool_start
            flush_line_buffer(line_buffer, in_code_block) if streaming_text
            streaming_text = false
            in_code_block = false
            line_buffer.clear
            name, input_data = args
            detail = format_tool_call(name, input_data)
            puts "#{TOOL_COLOR}  ⚡ #{detail}#{RESET}"

          when :tool_end
            name, result_str = args
            summary = truncate(result_str.to_s, 120)
            puts "#{RESULT_COLOR}  ↩ #{summary}#{RESET}" unless summary.start_with?("ok:")
          end
        end

        # Flush any remaining buffered text
        flush_line_buffer(line_buffer, in_code_block) if streaming_text

        # Non-streaming fallback: if no text was streamed (e.g. tool-only response),
        # render the final result as a single block
        unless streaming_text
          display = case result
                    when Hash then result.inspect
                    when nil then nil
                    when String then render_markdown(result)
                    else result.inspect
                    end
          puts "#{MANA_PREFIX}#{display}" if display
        end
      rescue LLMError, MaxIterationsError => e
        flush_line_buffer(line_buffer, in_code_block) if streaming_text
        puts "#{ERROR_COLOR}error: #{e.message}#{RESET}"
      end
    end
    private_class_method :run_mana

    # --- Markdown → ANSI rendering ---

    # Render a single line, handling code block state.
    # Returns the new in_code_block state.
    def self.render_line(line, in_code_block)
      if line.strip.start_with?("```")
        if in_code_block
          # End of code block — don't print the closing ```
          return false
        else
          # Start of code block — don't print the opening ```
          return true
        end
      end

      if in_code_block
        print "  #{CODE_COLOR}#{line}#{RESET}"
      else
        print render_markdown_inline(line)
      end
      in_code_block
    end
    private_class_method :render_line

    # Flush remaining text in the line buffer
    def self.flush_line_buffer(buffer, in_code_block)
      return if buffer.empty?
      text = buffer.dup
      buffer.clear
      if in_code_block
        print "  #{CODE_COLOR}#{text}#{RESET}"
      else
        print render_markdown_inline(text)
      end
      puts
    end
    private_class_method :flush_line_buffer

    # Convert inline markdown to ANSI codes.
    # Handles **bold**, `inline code` (with negative lookbehind to skip ```),
    # and # headings. Intentionally minimal — just enough for readable terminal output.
    def self.render_markdown_inline(text)
      text
        .gsub(/\*\*(.+?)\*\*/, "#{BOLD}\\1#{RESET}")
        .gsub(/(?<!`)`([^`]+)`(?!`)/, "#{CODE_COLOR}\\1#{RESET}")
        .gsub(/^\#{1,3}\s+(.+)/) { BOLD + $1 + RESET }
    end
    private_class_method :render_markdown_inline

    # Render a complete block of markdown text (for non-streaming results)
    def self.render_markdown(text)
      lines = text.lines
      result = +""
      in_code = false
      lines.each do |line|
        stripped = line.strip
        if stripped.start_with?("```")
          in_code = !in_code
          next
        end
        if in_code
          result << "  #{CODE_COLOR}#{line.rstrip}#{RESET}\n"
        else
          result << render_markdown_inline(line.rstrip) << "\n"
        end
      end
      result.chomp
    end
    private_class_method :render_markdown

    # --- Tool formatting helpers ---

    def self.format_tool_call(name, input)
      case name
      when "call_func"
        func = input[:name] || input["name"]
        args = input[:args] || input["args"] || []
        body = input[:body] || input["body"]
        desc = func.to_s
        desc += "(#{args.map(&:inspect).join(', ')})" if args.any?
        desc += " { #{truncate(body, 40)} }" if body
        desc
      # Display read_var as just the name, write_var as an assignment
      when "read_var", "write_var"
        var = input[:name] || input["name"]
        val = input[:value] || input["value"]
        val ? "#{var} = #{truncate(val.inspect, 60)}" : var.to_s
      when "read_attr", "write_attr"
        obj = input[:obj] || input["obj"]
        attr = input[:attr] || input["attr"]
        "#{obj}.#{attr}"
      when "remember"
        content = input[:content] || input["content"]
        "remember: #{truncate(content.to_s, 60)}"
      when "knowledge"
        topic = input[:topic] || input["topic"]
        "knowledge(#{topic})"
      else
        name.to_s
      end
    end
    private_class_method :format_tool_call

    def self.truncate(str, max)
      str.length > max ? "#{str[0, max]}..." : str
    end
    private_class_method :truncate
  end
end
