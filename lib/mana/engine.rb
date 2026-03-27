# frozen_string_literal: true

require "json"

module Mana
  # The Engine handles ~"..." prompts by calling an LLM with tool-calling
  # to interact with Ruby variables in the caller's binding.
  class Engine
    attr_reader :config, :binding

    include Mana::BindingHelpers
    include Mana::PromptBuilder
    include Mana::ToolHandler

    TOOLS = [
      {
        name: "read_var",
        description: "Read a variable value from the Ruby scope.",
        input_schema: {
          type: "object",
          properties: { name: { type: "string", description: "Variable name" } },
          required: ["name"]
        }
      },
      {
        name: "write_var",
        description: "Write a JSON-serializable value (string, number, boolean, array, hash, nil) to a variable. Cannot store lambdas, procs, or Ruby objects — use call_func with define_method for functions.",
        input_schema: {
          type: "object",
          properties: {
            name: { type: "string", description: "Variable name" },
            value: { description: "Value to assign (any JSON type)" }
          },
          required: %w[name value]
        }
      },
      {
        name: "read_attr",
        description: "Read an attribute from a Ruby object.",
        input_schema: {
          type: "object",
          properties: {
            obj: { type: "string", description: "Variable name holding the object" },
            attr: { type: "string", description: "Attribute name to read" }
          },
          required: %w[obj attr]
        }
      },
      {
        name: "write_attr",
        description: "Set an attribute on a Ruby object.",
        input_schema: {
          type: "object",
          properties: {
            obj: { type: "string", description: "Variable name holding the object" },
            attr: { type: "string", description: "Attribute name to set" },
            value: { description: "Value to assign" }
          },
          required: %w[obj attr value]
        }
      },
      {
        name: "call_func",
        description: "Call a Ruby method/function. Use body to pass a block. To define new methods: call_func(name: 'define_method', args: ['method_name'], body: '|args| code').",
        input_schema: {
          type: "object",
          properties: {
            name: { type: "string", description: "Function/method name" },
            args: { type: "array", description: "Positional arguments", items: {} },
            kwargs: { type: "object", description: "Keyword arguments (e.g. {sql: '...', limit: 10})" },
            body: { type: "string", description: "Ruby code block body, passed as &block. Use |params| syntax. Example: '|x| x * 2'" }
          },
          required: ["name"]
        }
      },
      {
        name: "done",
        description: "Signal that the task is complete. Always include the result — this is the value returned to the Ruby program.",
        input_schema: {
          type: "object",
          properties: {
            result: { description: "The answer or result to return. Always provide this." }
          }
        }
      },
      {
        name: "error",
        description: "Signal that the task cannot be completed. Call this when you encounter an unrecoverable problem. The message will be raised as an exception in the Ruby program.",
        input_schema: {
          type: "object",
          properties: {
            message: { type: "string", description: "Description of the error" }
          },
          required: ["message"]
        }
      },
      {
        name: "eval",
        description: "Execute Ruby code directly in the caller's binding. Returns the result of the last expression. Use this for anything that's easier to express as Ruby code than as individual tool calls.",
        input_schema: {
          type: "object",
          properties: {
            code: { type: "string", description: "Ruby code to execute" }
          },
          required: ["code"]
        }
      },
      {
        name: "knowledge",
        description: "Query the knowledge base. Covers ruby-mana internals, Ruby documentation (ri), and runtime introspection of classes/modules.",
        input_schema: {
          type: "object",
          properties: {
            topic: { type: "string", description: "Topic to look up. Examples: 'memory', 'tools', 'ruby', 'Array#map', 'Enumerable', 'Hash'" }
          },
          required: ["topic"]
        }
      }
    ].freeze

    # Separated from TOOLS because it's conditionally excluded in incognito mode
    REMEMBER_TOOL = {
      name: "remember",
      description: "Store a fact in long-term memory. This memory persists across script executions. Use when the user explicitly asks to remember something.",
      input_schema: {
        type: "object",
        properties: { content: { type: "string", description: "The fact to remember" } },
        required: ["content"]
      }
    }.freeze


    class << self
      # Entry point for ~"..." prompts. Routes to mock handler or real LLM engine.
      def run(prompt, caller_binding)
        if Mana.current_mock
          return new(caller_binding).handle_mock(prompt)
        end

        # Normal mode: execute via the LLM engine
        new(caller_binding).execute(prompt)
      end

      # Built-in tools + remember (conditional)
      def all_tools
        tools = TOOLS.dup
        tools << REMEMBER_TOOL unless Memory.incognito?
        tools
      end

      # Query the runtime knowledge base
      def knowledge(topic)
        Mana::Knowledge.query(topic)
      end
    end

    # Capture the caller's binding, config, source path, and incognito state
    def initialize(caller_binding, config = Mana.config)
      @binding = caller_binding
      @config = config
      @caller_path = caller_source_path
      @incognito = Memory.incognito?
    end

    # Main execution loop: build context, call LLM, handle tool calls, iterate until done.
    # Optional &on_text block receives streaming text deltas for real-time display.
    def execute(prompt, &on_text)
      # Track nesting depth to isolate memory for nested ~"..." calls
      Thread.current[:mana_depth] ||= 0
      Thread.current[:mana_depth] += 1
      nested = Thread.current[:mana_depth] > 1
      outer_memory = nil  # defined here so ensure block always has access

      # Nested calls get fresh short-term memory but share long-term
      if nested && !@incognito
        outer_memory = Thread.current[:mana_memory]
        inner_memory = Mana::Memory.new
        long_term = outer_memory&.long_term || []
        inner_memory.instance_variable_set(:@long_term, long_term)
        inner_memory.instance_variable_set(:@next_id, (long_term.map { |m| m[:id] }.max || 0) + 1)
        Thread.current[:mana_memory] = inner_memory
      end

      # Extract <var> references from the prompt and read their current values
      context = build_context(prompt)
      system_prompt = build_system_prompt(context)

      memory = @incognito ? nil : Memory.current
      # Wait for any in-progress background compaction before reading messages
      memory&.wait_for_compaction

      messages = memory ? memory.short_term : []

      # Strip trailing unpaired tool_use messages from prior calls.
      # Both Anthropic and OpenAI reject requests where the last assistant message
      # has tool_use blocks without corresponding tool_result responses.
      while messages.last && messages.last[:role] == "assistant" &&
            messages.last[:content].is_a?(Array) &&
            messages.last[:content].any? { |b| (b[:type] || b["type"]) == "tool_use" }
        messages.pop
      end

      # Track where we started in messages — rollback on failure
      messages_start_size = messages.size
      messages << { role: "user", content: prompt }

      iterations = 0
      done_result = nil
      @written_vars = {}  # Track write_var calls for return value

      vlog("═" * 60)
      vlog("🚀 Prompt: #{prompt}")
      vlog("📡 Backend: #{@config.effective_base_url} / #{@config.model}")

      # --- Main tool-calling loop ---
      loop do
        iterations += 1
        @_iteration = iterations
        raise MaxIterationsError, "exceeded #{@config.max_iterations} iterations" if iterations > @config.max_iterations

        response = llm_call(system_prompt, messages, &on_text)
        tool_uses = extract_tool_uses(response)

        if tool_uses.empty?
          # In streaming/chat mode, text-only responses are fine — just accept them
          if on_text
            messages << { role: "assistant", content: response }
            text = response.is_a?(Array) ? response.filter_map { |b| b[:text] || b["text"] }.join("\n") : response.to_s
            done_result = text unless text.empty?
            break
          end
          # In script mode (~"..."), nudge the LLM to use tools
          if iterations == 1 && @written_vars.empty?
            messages << { role: "assistant", content: response }
            messages << { role: "user", content: "You must use the provided tools to complete this task. Do not just describe the answer in text." }
            next
          end
          # LLM refused to use tools after nudge — extract text and raise
          text = response.is_a?(Array) ? response.filter_map { |b| b[:text] || b["text"] }.join("\n") : response.to_s
          raise Mana::LLMError, "LLM did not use tools: #{text.slice(0, 200)}"
        end

        # Append assistant message with tool_use blocks
        messages << { role: "assistant", content: response }

        # Process each tool use and collect results
        tool_results = tool_uses.map do |tu|
          if on_text
            case tu[:name]
            when "done", "error"
              # handled separately
            else
              on_text.call(:tool_start, tu[:name], tu[:input])
            end
          end
          result = handle_effect(tu, memory)
          if on_text && !%w[done error].include?(tu[:name])
            on_text.call(:tool_end, tu[:name], result)
          end
          done_result = (tu[:input][:result] || tu[:input]["result"]) if tu[:name] == "done"
          { type: "tool_result", tool_use_id: tu[:id], content: result.to_s }
        end

        # Send tool results back to the LLM as a user message
        messages << { role: "user", content: tool_results }
        # Exit loop when the LLM signals completion via the "done" tool
        break if tool_uses.any? { |t| t[:name] == "done" }
      end

      # Append a final assistant summary so LLM has full context next call
      if memory && done_result
        messages << { role: "assistant", content: [{ type: "text", text: "Done: #{done_result}" }] }
      end

      # Schedule compaction if needed (runs in background, skip for nested)
      memory&.schedule_compaction unless nested

      # Return written variables so Ruby 4.0+ users can capture them:
      #   result = ~"compute average and store in <result>"
      # Single write -> return the value directly; multiple -> return Hash.
      if @written_vars.size == 1
        @written_vars.values.first
      elsif @written_vars.size > 1
        @written_vars.transform_keys(&:to_sym)
      else
        # No writes — return the done() result
        done_result
      end
    rescue => e
      # Rollback: remove messages added during this failed call so they don't
      # pollute short-term memory for subsequent prompts
      if memory && messages.size > messages_start_size
        messages.slice!(messages_start_size..)
      end
      raise e
    ensure
      # Restore outer memory when exiting a nested call
      if nested && !@incognito
        Thread.current[:mana_memory] = outer_memory
      end
      Thread.current[:mana_depth] -= 1 if Thread.current[:mana_depth]
    end

    # Mock handling — finds a matching stub and writes its values into the caller's binding.
    def handle_mock(prompt)
      mock = Mana.current_mock
      stub = mock.match(prompt)

      # No matching stub found — raise with a helpful hint
      unless stub
        truncated = prompt.length > 60 ? "#{prompt[0..57]}..." : prompt
        raise MockError, "No mock matched: \"#{truncated}\"\n  Add: mock_prompt \"#{truncated}\", _return: \"...\""
      end

      # Evaluate stub: block-based stubs receive the prompt, hash-based return a copy
      values = if stub.block
        stub.block.call(prompt)
      else
        stub.values.dup
      end

      # Extract the special _return key (the value returned to the caller)
      return_value = values.delete(:_return)

      # Write remaining key-value pairs as local variables in the caller's scope
      values.each do |name, value|
        write_local(name.to_s, value)
      end

      # Record in short-term memory if not incognito
      if !@incognito
        memory = Memory.current
        if memory
          memory.short_term << { role: "user", content: prompt }
          memory.short_term << { role: "assistant", content: [{ type: "text", text: "Done: #{return_value || values.inspect}" }] }
        end
      end

      # Return _return value if set, otherwise the first written value
      return_value || values.values.first
    end

    private

    # --- LLM Client ---

    # Send a request to the LLM backend and log the response.
    # When &on_text is provided and the backend supports streaming, streams text deltas.
    def llm_call(system, messages, &on_text)
      vlog("\n#{"─" * 60}")
      vlog("🔄 LLM call ##{@_iteration} → #{@config.model}")
      backend = Backends::Base.for(@config)

      result = if on_text && backend.respond_to?(:chat_stream)
        backend.chat_stream(
          system: system,
          messages: messages,
          tools: self.class.all_tools,
          model: @config.model,
          max_tokens: 4096
        ) do |event|
          on_text.call(:text, event[:text]) if event[:type] == :text_delta
        end
      else
        backend.chat(
          system: system,
          messages: messages,
          tools: self.class.all_tools,
          model: @config.model,
          max_tokens: 4096
        )
      end

      result.each do |block|
        type = block[:type] || block["type"]
        case type
        when "text"
          text = block[:text] || block["text"]
          vlog("💬 #{text}") if text
        when "tool_use"
          name = block[:name] || block["name"]
          input = block[:input] || block["input"]
          vlog("🔧 #{name}(#{summarize_input(input)})")
        end
      end
      result
    end

    include Mana::Logger

    # Extract tool_use blocks from the LLM response content array
    def extract_tool_uses(content)
      return [] unless content.is_a?(Array)

      content
        .select { |block| (block[:type] || block["type"]) == "tool_use" }
        .map { |block|
          {
            id: block[:id] || block["id"],
            name: block[:name] || block["name"],
            input: block[:input] || block["input"] || {}
          }
        }
    end
  end
end
