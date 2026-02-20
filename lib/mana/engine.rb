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
    end

    def initialize(prompt, caller_binding)
      @prompt = prompt
      @binding = caller_binding
      @config = Mana.config
    end

    def execute
      context = build_context(@prompt)
      system_prompt = build_system_prompt(context)
      messages = [{ role: "user", content: @prompt }]

      iterations = 0
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
          result = handle_effect(tu)
          { type: "tool_result", tool_use_id: tu[:id], content: result.to_s }
        end

        messages << { role: "user", content: tool_results }

        break if tool_uses.any? { |t| t[:name] == "done" }
      end
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

      unless context.empty?
        parts << ""
        parts << "Current variable values:"
        context.each { |k, v| parts << "  #{k} = #{v}" }
      end

      parts.join("\n")
    end

    # --- Effect Handling ---

    def handle_effect(tool_use)
      name = tool_use[:name]
      input = tool_use[:input] || {}

      # Check handler stack first
      handler = self.class.handler_stack.last
      return handler.call(name, input) if handler && handler.respond_to?(:call)

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
        serialize_value(obj.public_send(input["attr"]))

      when "write_attr"
        obj = resolve(input["obj"])
        obj.public_send("#{input['attr']}=", input["value"])
        "ok: #{input['obj']}.#{input['attr']} = #{input['value'].inspect}"

      when "call_func"
        func = input["name"]
        args = input["args"] || []
        result = @binding.eval("method(:#{func})").call(*args)
        serialize_value(result)

      when "done"
        input["result"].to_s

      else
        "error: unknown tool #{name}"
      end
    rescue => e
      "error: #{e.class}: #{e.message}"
    end

    # --- Binding Helpers ---

    def resolve(name)
      if @binding.local_variable_defined?(name.to_sym)
        @binding.local_variable_get(name.to_sym)
      else
        @binding.eval(name.to_s)
      end
    end

    def write_local(name, value)
      sym = name.to_sym
      unless @binding.local_variable_defined?(sym)
        @binding.eval("#{name} = nil")
      end
      @binding.local_variable_set(sym, value)
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
        attrs = (val.class.instance_methods(false) - [:inspect, :to_s])
          .select { |m| val.class.instance_method(m).arity == 0 }
          .reject { |m| m.to_s.end_with?("=") }
        obj_repr = attrs.map do |a|
          "#{a}: #{val.public_send(a).inspect}" rescue nil
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
        tools: TOOLS,
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
