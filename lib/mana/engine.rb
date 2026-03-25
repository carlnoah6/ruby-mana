# frozen_string_literal: true

require "json"

module Mana
  # The Engine handles ~"..." prompts by calling an LLM with tool-calling
  # to interact with Ruby variables in the caller's binding.
  class Engine
    attr_reader :config, :binding

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
        description: "Write a value to a variable in the Ruby scope. Creates the variable if it doesn't exist.",
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
        description: "Call a Ruby method/function available in the current scope.",
        input_schema: {
          type: "object",
          properties: {
            name: { type: "string", description: "Function/method name" },
            args: { type: "array", description: "Arguments to pass", items: {} }
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
      }
    ].freeze

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

      # Built-in tools + remember + any registered custom effects
      def all_tools
        tools = TOOLS.dup
        tools << REMEMBER_TOOL unless Memory.incognito?
        tools + Mana::EffectRegistry.tool_definitions
      end
    end

    # Capture the caller's binding, config, source path, and incognito state
    def initialize(caller_binding, config = Mana.config)
      @binding = caller_binding
      @config = config
      @caller_path = caller_source_path
      @incognito = Memory.incognito?
    end

    # Main execution loop: build context, call LLM, handle tool calls, iterate until done
    def execute(prompt)
      # Track nesting depth to isolate memory for nested ~"..." calls
      Thread.current[:mana_depth] ||= 0
      Thread.current[:mana_depth] += 1
      nested = Thread.current[:mana_depth] > 1

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

      # Ensure messages don't end with an unpaired tool_use (causes API 400 error)
      while messages.last && messages.last[:role] == "assistant" &&
            messages.last[:content].is_a?(Array) &&
            messages.last[:content].any? { |b| (b[:type] || b["type"]) == "tool_use" }
        messages.pop
      end

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

        response = llm_call(system_prompt, messages)
        tool_uses = extract_tool_uses(response)

        if tool_uses.empty?
          # Model returned text without calling any tools.
          # On the first iteration with no writes yet, nudge it to use tools.
          if iterations == 1 && @written_vars.empty?
            messages << { role: "assistant", content: response }
            messages << { role: "user", content: "You must use the provided tools (read_var, write_var, done) to complete this task. Do not just describe the answer in text." }
            next
          end
          # Otherwise, accept the text-only response and exit the loop
          break
        end

        # Append assistant message with tool_use blocks
        messages << { role: "assistant", content: response }

        # Process each tool use and collect results
        tool_results = tool_uses.map do |tu|
          result = handle_effect(tu, memory)
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

    # --- Context Building ---

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
        "You are embedded inside a Ruby program. You interact with the program's live state using the provided tools.",
        "",
        "Rules:",
        "- Use read_var / read_attr to inspect variables and objects.",
        "- Use write_var to create or update variables in the Ruby scope.",
        "- Use write_attr to set attributes on Ruby objects.",
        "- Use call_func to call Ruby methods listed below. Only call functions that are explicitly listed — do NOT guess or try to discover functions by calling methods like `methods`, `local_variables`, etc.",
        "- Call done(result: ...) when the task is complete. ALWAYS put the answer in the result field — it is the return value of ~\"...\". If no <var> is referenced, the done result is the only way to return a value.",
        "- When the user references <var>, that's a variable in scope.",
        "- If a referenced variable doesn't exist yet, the user expects you to create it with write_var.",
        "- Be precise with types: use numbers for numeric values, arrays for lists, strings for text.",
        "- Respond in the same language as the user's prompt unless explicitly told otherwise.",
        "- PRIORITY: The user's current prompt ALWAYS overrides any prior context, conversation history, or long-term memories. Treat it like Ruby's inner scope shadowing outer scope."
      ]

      if @incognito
        parts << ""
        parts << "You are in incognito mode. The remember tool is disabled. No memories will be loaded or saved."
      else
        memory = Memory.current
        # Inject memory context when available
        if memory
          # Add compaction summaries from prior conversations
          unless memory.summaries.empty?
            parts << ""
            parts << "Previous conversation summary:"
            memory.summaries.each { |s| parts << "  #{s}" }
          end

          # Add persistent long-term facts
          unless memory.long_term.empty?
            parts << ""
            parts << "Long-term memories (persistent background context):"
            memory.long_term.each { |m| parts << "- #{m[:content]}" }
            parts << "NOTE: Long-term memories are background defaults. The user's current prompt ALWAYS takes priority. If the prompt conflicts with a memory (e.g. memory says Japanese but prompt says Chinese), follow the prompt."
          end

          unless memory.long_term.empty?
            parts << ""
            parts << "You have a `remember` tool to store new facts in long-term memory when the user asks."
          end
        end
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

      # Append custom effect descriptions so the LLM knows about user-defined tools
      custom_effects = Mana::EffectRegistry.tool_definitions
      unless custom_effects.empty?
        parts << ""
        parts << "Custom tools available:"
        custom_effects.each do |t|
          params = (t[:input_schema][:properties] || {}).keys.join(", ")
          parts << "  #{t[:name]}(#{params}) — #{t[:description]}"
        end
      end

      parts.join("\n")
    end

    # --- Effect Handling ---

    # Dispatch a single tool call from the LLM.
    # Checks custom effects first, then handles built-in tools.
    def handle_effect(tool_use, memory = nil)
      name = tool_use[:name]
      input = tool_use[:input] || {}
      # Normalize keys to strings for consistent access
      input = input.transform_keys(&:to_s) if input.is_a?(Hash)

      # Check custom effect registry before built-in tools
      handled, result = Mana::EffectRegistry.handle(name, input)
      return serialize_value(result) if handled

      case name
      when "read_var"
        # Read a variable from the caller's binding and return its serialized value
        val = serialize_value(resolve(input["name"]))
        vlog("   ↩ #{input['name']} = #{val}")
        val

      when "write_var"
        # Write a value to the caller's binding and track it for the return value
        var_name = input["name"]
        value = input["value"]
        write_local(var_name, value)
        @written_vars[var_name] = value
        vlog("   ✅ #{var_name} = #{value.inspect}")
        "ok: #{var_name} = #{value.inspect}"

      when "read_attr"
        # Read an attribute (public method) from a Ruby object in scope
        obj = resolve(input["obj"])
        validate_name!(input["attr"])
        serialize_value(obj.public_send(input["attr"]))

      when "write_attr"
        # Set an attribute (public setter) on a Ruby object in scope
        obj = resolve(input["obj"])
        validate_name!(input["attr"])
        obj.public_send("#{input['attr']}=", input["value"])
        "ok: #{input['obj']}.#{input['attr']} = #{input['value'].inspect}"

      when "call_func"
        func = input["name"]
        args = input["args"] || []
        policy = @config.security_policy

        # Handle chained calls (e.g. Time.now, Time.now.to_s, File.read)
        if func.include?(".")
          # Split into receiver constant and method chain for security check
          first_dot = func.index(".")
          receiver_name = func[0...first_dot]
          rest = func[(first_dot + 1)..]
          methods_chain = rest.split(".")
          first_method = methods_chain.first

          # Enforce security policy on the receiver+method pair
          if policy.receiver_call_blocked?(receiver_name, first_method)
            raise NameError, "'#{receiver_name}.#{first_method}' is blocked by security policy (level #{policy.level}: #{policy.preset})"
          end
          if policy.method_blocked?(first_method)
            raise NameError, "'#{first_method}' is blocked by security policy"
          end

          # Resolve the receiver constant and call the first method with args
          receiver = @binding.eval(receiver_name) rescue raise(NameError, "unknown constant '#{receiver_name}'")
          result = receiver.public_send(first_method.to_sym, *args)

          # Chain remaining methods without args (e.g. .to_s, .strftime)
          methods_chain[1..].each do |m|
            result = result.public_send(m.to_sym)
          end

          vlog("   ↩ #{func}(#{args.map(&:inspect).join(', ')}) → #{result.inspect}")
          return serialize_value(result)
        end

        # Simple (non-chained) function call
        validate_name!(func)
        if policy.method_blocked?(func)
          raise NameError, "'#{func}' is blocked by security policy (level #{policy.level}: #{policy.preset})"
        end

        # Try local variable (lambdas/procs) first, then receiver methods
        callable = if @binding.local_variables.include?(func.to_sym)
                     # Local lambda/proc takes priority
                     @binding.local_variable_get(func.to_sym)
                   elsif @binding.receiver.respond_to?(func.to_sym, true)
                     # Fall back to method defined on the receiver (self)
                     @binding.receiver.method(func.to_sym)
                   else
                     raise NameError, "undefined function '#{func}'"
                   end
        result = callable.call(*args)
        vlog("   ↩ #{func}(#{args.map(&:inspect).join(', ')}) → #{result.inspect}")
        serialize_value(result)

      when "remember"
        # Store a fact in long-term memory (persistent across executions)
        if @incognito
          "Memory not saved (incognito mode)"
        elsif memory
          entry = memory.remember(input["content"])
          "Remembered (id=#{entry[:id]}): #{input['content']}"
        else
          "Memory not available"
        end

      when "done"
        # Signal task completion; the result becomes the return value
        vlog("🏁 Done: #{input['result'].inspect}")
        vlog("═" * 60)
        input["result"].to_s

      else
        "error: unknown tool #{name}"
      end
    rescue => e
      # Return errors as strings so the LLM can see and react to them
      "error: #{e.class}: #{e.message}"
    end

    # --- Binding Helpers ---

    VALID_IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_]*\z/

    # Ensure a name is a valid Ruby identifier (prevents injection)
    def validate_name!(name)
      raise Mana::Error, "invalid identifier: #{name.inspect}" unless name.match?(VALID_IDENTIFIER)
    end

    # Resolve a name to a value: try local variable first, then receiver method
    def resolve(name)
      validate_name!(name)
      if @binding.local_variable_defined?(name.to_sym)
        # Found as a local variable in the caller's binding
        @binding.local_variable_get(name.to_sym)
      elsif @binding.receiver.respond_to?(name.to_sym, true)
        # Found as a method on the caller's self (instance method, attr_reader, etc.)
        @binding.receiver.send(name.to_sym)
      else
        raise NameError, "undefined variable or method '#{name}'"
      end
    end

    # Write a value into the caller's binding, with Ruby 4.0+ singleton method fallback
    def write_local(name, value)
      validate_name!(name)
      sym = name.to_sym

      @binding.local_variable_set(sym, value)

      # Ruby 4.0+: local_variable_set can no longer create new locals visible
      # in the caller's scope. Always define a singleton method as fallback.
      receiver = @binding.eval("self")
      old_verbose, $VERBOSE = $VERBOSE, nil
      receiver.define_singleton_method(sym) { value }
      $VERBOSE = old_verbose
    end

    # Find the user's source file by walking up the call stack.
    # Used for introspecting available methods in the caller's code.
    def caller_source_path
      # Try binding's source_location first (most direct)
      loc = @binding.source_location
      return loc[0] if loc.is_a?(Array)

      # Fallback: scan caller_locations, skip frames inside the mana gem itself
      caller_locations(4, 20)&.each do |frame|
        path = frame.absolute_path || frame.path
        next if path.nil? || path.include?("mana/")
        return path
      end
      nil
    end

    # Serialize a Ruby value to a string representation the LLM can understand.
    # Handles primitives, collections, and arbitrary objects (via ivar inspection).
    def serialize_value(val)
      case val
      when Time
        # Format Time as a human-readable timestamp string
        val.strftime("%Y-%m-%d %H:%M:%S %z").inspect
      when String, Integer, Float, TrueClass, FalseClass, NilClass
        # Primitives: use Ruby's built-in inspect
        val.inspect
      when Symbol
        # Convert symbol to string for LLM readability
        val.to_s.inspect
      when Array
        # Recursively serialize each element
        "[#{val.map { |v| serialize_value(v) }.join(', ')}]"
      when Hash
        # Recursively serialize key-value pairs
        pairs = val.map { |k, v| "#{serialize_value(k)} => #{serialize_value(v)}" }
        "{#{pairs.join(', ')}}"
      else
        # Arbitrary object: show class name and instance variables
        ivars = val.instance_variables
        obj_repr = ivars.map do |ivar|
          attr_name = ivar.to_s.delete_prefix("@")
          "#{attr_name}: #{val.instance_variable_get(ivar).inspect}" rescue nil
        end.compact.join(", ")
        "#<#{val.class} #{obj_repr}>"
      end
    end

    # --- LLM Client ---

    # Send a request to the LLM backend and log the response
    def llm_call(system, messages)
      vlog("\n#{"─" * 60}")
      vlog("🔄 LLM call ##{@_iteration} → #{@config.model}")
      backend = Backends.for(@config)
      result = backend.chat(
        system: system,
        messages: messages,
        tools: self.class.all_tools,
        model: @config.model,
        max_tokens: 4096
      )
      result.each do |block|
        type = block[:type] || block["type"]
        case type
        when "text"
          text = block[:text] || block["text"]
          vlog("💬 #{text}")
        when "tool_use"
          name = block[:name] || block["name"]
          input = block[:input] || block["input"]
          vlog("🔧 #{name}(#{input.inspect})")
        end
      end
      result
    end

    # Log a debug message to stderr (only when verbose mode is enabled)
    def vlog(msg)
      return unless @config.verbose

      $stderr.puts "\e[2m[mana] #{msg}\e[0m"
    end

    # Extract tool_use blocks from the LLM response content array
    def extract_tool_uses(content)
      return [] unless content.is_a?(Array)

      content
        .select { |block| block[:type] == "tool_use" }
        .map { |block| { id: block[:id], name: block[:name], input: block[:input] || {} } }
    end
  end
end
