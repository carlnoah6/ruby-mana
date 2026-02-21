# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Mana
  class Engine
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
        description: "Signal that the task is complete.",
        input_schema: {
          type: "object",
          properties: {
            result: { description: "Optional return value" }
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
      def run(prompt, caller_binding)
        new(prompt, caller_binding).execute
      end

      def handler_stack
        Thread.current[:mana_handlers] ||= []
      end

      def with_handler(handler = nil, **opts, &block)
        handler_stack.push(handler)
        block.call
      ensure
        handler_stack.pop
      end

      # Built-in tools + remember + any registered custom effects
      def all_tools
        tools = TOOLS.dup
        tools << REMEMBER_TOOL unless Memory.incognito?
        tools + Mana::EffectRegistry.tool_definitions
      end
    end

    def initialize(prompt, caller_binding)
      @prompt = prompt
      @binding = caller_binding
      @config = Mana.config
      @caller_path = caller_source_path
      @incognito = Memory.incognito?
    end

    def execute
      context = build_context(@prompt)
      system_prompt = build_system_prompt(context)

      # Use memory's short_term messages (auto per-thread), or fresh if incognito
      memory = @incognito ? nil : Memory.current
      memory&.wait_for_compaction

      messages = memory ? memory.short_term : []
      messages << { role: "user", content: @prompt }

      iterations = 0
      done_result = nil

      loop do
        iterations += 1
        raise MaxIterationsError, "exceeded #{@config.max_iterations} iterations" if iterations > @config.max_iterations

        response = llm_call(system_prompt, messages)
        tool_uses = extract_tool_uses(response)

        break if tool_uses.empty?

        # Append assistant message
        messages << { role: "assistant", content: response }

        # Process each tool use
        tool_results = tool_uses.map do |tu|
          result = handle_effect(tu, memory)
          done_result = (tu[:input][:result] || tu[:input]["result"]) if tu[:name] == "done"
          { type: "tool_result", tool_use_id: tu[:id], content: result.to_s }
        end

        messages << { role: "user", content: tool_results }

        break if tool_uses.any? { |t| t[:name] == "done" }
      end

      # Append a final assistant summary so LLM has full context next call
      if memory && done_result
        messages << { role: "assistant", content: [{ type: "text", text: "Done: #{done_result}" }] }
      end

      # Schedule compaction if needed (runs in background)
      memory&.schedule_compaction

      done_result
    end

    private

    # --- Context Building ---

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

    def build_system_prompt(context)
      parts = [
        "You are embedded inside a Ruby program. You interact with the program's live state using the provided tools.",
        "",
        "Rules:",
        "- Use read_var / read_attr to inspect variables and objects.",
        "- Use write_var to create or update variables in the Ruby scope.",
        "- Use write_attr to set attributes on Ruby objects.",
        "- Use call_func to call Ruby methods available in scope.",
        "- Call done when the task is complete.",
        "- When the user references <var>, that's a variable in scope.",
        "- If a referenced variable doesn't exist yet, the user expects you to create it with write_var.",
        "- Be precise with types: use numbers for numeric values, arrays for lists, strings for text."
      ]

      # Inject long-term memories or incognito notice
      if @incognito
        parts << ""
        parts << "You are in incognito mode. The remember tool is disabled. No memories will be loaded or saved."
      else
        memory = Memory.current
        if memory
          # Inject summaries from compaction
          unless memory.summaries.empty?
            parts << ""
            parts << "Previous conversation summary:"
            memory.summaries.each { |s| parts << "  #{s}" }
          end

          unless memory.long_term.empty?
            parts << ""
            parts << "Long-term memories (persistent across executions):"
            memory.long_term.each { |m| parts << "- #{m[:content]}" }
          end

          unless memory.long_term.empty? && @incognito
            parts << ""
            parts << "You have a `remember` tool to store new facts in long-term memory when the user asks."
          end
        end
      end

      unless context.empty?
        parts << ""
        parts << "Current variable values:"
        context.each { |k, v| parts << "  #{k} = #{v}" }
      end

      # Discover available functions from caller's source
      methods = begin
        Mana::Introspect.methods_from_file(@caller_path)
      rescue => _e
        []
      end
      unless methods.empty?
        parts << ""
        parts << Mana::Introspect.format_for_prompt(methods)
      end

      # List custom effects
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

    def handle_effect(tool_use, memory = nil)
      name = tool_use[:name]
      input = tool_use[:input] || {}
      # Normalize keys to strings for consistent access
      input = input.transform_keys(&:to_s) if input.is_a?(Hash)

      # Check handler stack first (legacy)
      handler = self.class.handler_stack.last
      return handler.call(name, input) if handler && handler.respond_to?(:call)

      # Check custom effect registry
      handled, result = Mana::EffectRegistry.handle(name, input)
      return serialize_value(result) if handled

      case name
      when "read_var"
        serialize_value(resolve(input["name"]))

      when "write_var"
        var_name = input["name"]
        value = input["value"]
        write_local(var_name, value)
        "ok: #{var_name} = #{value.inspect}"

      when "read_attr"
        obj = resolve(input["obj"])
        validate_name!(input["attr"])
        serialize_value(obj.public_send(input["attr"]))

      when "write_attr"
        obj = resolve(input["obj"])
        validate_name!(input["attr"])
        obj.public_send("#{input['attr']}=", input["value"])
        "ok: #{input['obj']}.#{input['attr']} = #{input['value'].inspect}"

      when "call_func"
        func = input["name"]
        validate_name!(func)
        args = input["args"] || []
        result = @binding.receiver.method(func.to_sym).call(*args)
        serialize_value(result)

      when "remember"
        if @incognito
          "Memory not saved (incognito mode)"
        elsif memory
          entry = memory.remember(input["content"])
          "Remembered (id=#{entry[:id]}): #{input['content']}"
        else
          "Memory not available"
        end

      when "done"
        input["result"].to_s

      else
        "error: unknown tool #{name}"
      end
    rescue => e
      "error: #{e.class}: #{e.message}"
    end

    # --- Binding Helpers ---

    VALID_IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_]*\z/

    def validate_name!(name)
      raise Mana::Error, "invalid identifier: #{name.inspect}" unless name.match?(VALID_IDENTIFIER)
    end

    def resolve(name)
      validate_name!(name)
      if @binding.local_variable_defined?(name.to_sym)
        @binding.local_variable_get(name.to_sym)
      elsif @binding.receiver.respond_to?(name.to_sym, true)
        @binding.receiver.send(name.to_sym)
      else
        raise NameError, "undefined variable or method '#{name}'"
      end
    end

    def write_local(name, value)
      validate_name!(name)
      @binding.local_variable_set(name.to_sym, value)
    end

    def caller_source_path
      # Walk up the call stack to find the first non-mana source file
      loc = @binding.source_location
      return loc[0] if loc.is_a?(Array)

      # Fallback: search caller_locations
      caller_locations(4, 20)&.each do |frame|
        path = frame.absolute_path || frame.path
        next if path.nil? || path.include?("mana/")
        return path
      end
      nil
    end

    def serialize_value(val)
      case val
      when String, Integer, Float, TrueClass, FalseClass, NilClass
        val.inspect
      when Symbol
        val.to_s.inspect
      when Array
        "[#{val.map { |v| serialize_value(v) }.join(', ')}]"
      when Hash
        pairs = val.map { |k, v| "#{serialize_value(k)} => #{serialize_value(v)}" }
        "{#{pairs.join(', ')}}"
      else
        ivars = val.instance_variables
        obj_repr = ivars.map do |ivar|
          attr_name = ivar.to_s.delete_prefix("@")
          "#{attr_name}: #{val.instance_variable_get(ivar).inspect}" rescue nil
        end.compact.join(", ")
        "#<#{val.class} #{obj_repr}>"
      end
    end

    # --- LLM Client ---

    def llm_call(system, messages)
      uri = URI("#{@config.base_url}/v1/messages")
      body = {
        model: @config.model,
        max_tokens: 4096,
        system: system,
        tools: self.class.all_tools,
        messages: messages
      }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 120

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req["x-api-key"] = @config.api_key
      req["anthropic-version"] = "2023-06-01"
      req.body = JSON.generate(body)

      res = http.request(req)
      raise LLMError, "HTTP #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

      parsed = JSON.parse(res.body, symbolize_names: true)
      parsed[:content] || []
    end

    def extract_tool_uses(content)
      return [] unless content.is_a?(Array)

      content
        .select { |block| block[:type] == "tool_use" }
        .map { |block| { id: block[:id], name: block[:name], input: block[:input] || {} } }
    end
  end
end
