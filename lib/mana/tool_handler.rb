# frozen_string_literal: true

module Mana
  # Dispatches LLM tool calls to their respective handlers.
  # Mixed into Engine as a private method.
  module ToolHandler
    private

    # Dispatch a single tool call from the LLM.
    def handle_effect(tool_use, memory = nil)
      name = tool_use[:name]
      input = tool_use[:input] || {}
      # Normalize keys to strings for consistent access
      input = input.transform_keys(&:to_s) if input.is_a?(Hash)

      case name
      when "read_var"
        # Read a variable from the caller's binding and return its serialized value
        val = serialize_value(resolve(input["name"]))
        vlog_value("   ↩ #{input['name']} =", val)
        val

      when "write_var"
        # Write a value to the caller's binding and track it for the return value
        var_name = input["name"]
        value = input["value"]
        write_local(var_name, value)
        @written_vars[var_name] = value
        vlog_value("   ✅ #{var_name} =", value)
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
        handle_call_func(input)

      when "knowledge"
        # Look up information about ruby-mana from the knowledge base
        self.class.knowledge(input["topic"])

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
        done_val = input["result"]
        vlog_value("🏁 Done:", done_val)
        vlog("═" * 60)
        input["result"].to_s

      when "error"
        # LLM signals it cannot complete the task — raise as exception
        msg = input["message"] || "LLM reported an error"
        vlog("❌ Error: #{msg}")
        vlog("═" * 60)
        raise Mana::LLMError, msg

      when "eval"
        result = @binding.eval(input["code"])
        vlog_value("   ↩ eval →", result)
        serialize_value(result)

      else
        "error: unknown tool #{name}"
      end
    rescue LLMError
      # LLMError must propagate to the caller (e.g. from the error tool)
      raise
    rescue ScriptError, StandardError => e
      # ScriptError covers SyntaxError, LoadError, NotImplementedError
      # StandardError covers everything else (NameError, TypeError, etc.)
      "error: #{e.class}: #{e.message}"
    end

    # Handle call_func tool: chained calls, block bodies, simple calls
    def handle_call_func(input)
      func = input["name"]
      args = input["args"] || []
      kwargs = (input["kwargs"] || {}).transform_keys(&:to_sym)
      body_code = input["body"]
      block = @binding.eval("proc { #{body_code} }") if body_code

      # Handle chained calls (e.g. Time.now, Array.new, File.read)
      if func.include?(".")
        return handle_chained_call(func, args, block)
      end

      # Handle body parameter for simple (non-chained) function calls
      if body_code
        validate_name!(func)
        receiver = @binding.receiver
        result = receiver.send(func.to_sym, *args, &block)
        vlog("   ↩ #{func}(#{args.inspect}) with body → #{result.inspect}")
        return serialize_value(result)
      end

      # Simple (non-chained) function call
      validate_name!(func)

      # Binding-sensitive method: local_variables returns scope-dependent results
      if func == "local_variables"
        return handle_local_variables
      end

      # Try local variable (lambdas/procs) first, then receiver methods
      callable = if @binding.local_variables.include?(func.to_sym)
                   @binding.local_variable_get(func.to_sym)
                 elsif @binding.receiver.respond_to?(func.to_sym, true)
                   @binding.receiver.method(func.to_sym)
                 else
                   raise NameError, "undefined function '#{func}'"
                 end
      result = kwargs.empty? ? callable.call(*args) : callable.call(*args, **kwargs)
      call_desc = args.map(&:inspect).concat(kwargs.map { |k, v| "#{k}: #{v.inspect}" }).join(", ")
      vlog_value("   ↩ #{func}(#{call_desc}) →", result)
      serialize_value(result)
    end

    # Handle chained method calls like Time.now, Array.new(10) { rand }
    def handle_chained_call(func, args, block)
      first_dot = func.index(".")
      receiver_name = func[0...first_dot]
      rest = func[(first_dot + 1)..]
      methods_chain = rest.split(".")
      first_method = methods_chain.first

      # Validate receiver is a simple constant name (e.g. "Time", "File", "Math")
      unless receiver_name.match?(/\A[A-Z][A-Za-z0-9_]*(::[A-Z][A-Za-z0-9_]*)*\z/)
        raise NameError, "'#{receiver_name}' is not a valid constant name"
      end

      begin
        receiver = @binding.eval(receiver_name)
      rescue => e
        raise NameError, "cannot resolve '#{receiver_name}': #{e.message}"
      end
      result = receiver.public_send(first_method.to_sym, *args, &block)

      # Chain remaining methods without args (e.g. .to_s, .strftime)
      methods_chain[1..].each do |m|
        result = result.public_send(m.to_sym)
      end

      vlog_value("   ↩ #{func}(#{args.map(&:inspect).join(', ')}) →", result)
      serialize_value(result)
    end

    # Handle local_variables call with Mana-created singleton method tracking
    def handle_local_variables
      result = @binding.local_variables.map(&:to_s)
      receiver = @binding.receiver
      if receiver.instance_variable_defined?(:@__mana_vars__)
        result = (result + receiver.instance_variable_get(:@__mana_vars__).map(&:to_s)).uniq
      end
      vlog("   ↩ local_variables() → #{result.size} variables")
      serialize_value(result)
    end
  end
end
