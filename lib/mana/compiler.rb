# frozen_string_literal: true

require "fileutils"
require "digest"

module Mana
  # Compiler for `mana def` — LLM generates method implementations on first call,
  # caches them as real .rb files, and replaces the method with native Ruby.
  #
  # Usage:
  #   mana def fibonacci(n)
  #     ~"return an array of the first n Fibonacci numbers"
  #   end
  #
  #   fibonacci(10)  # first call → LLM generates code → cached → executed
  #   fibonacci(20)  # subsequent calls → pure Ruby, zero API overhead
  #
  #   Mana.source(:fibonacci)  # view generated source
  module Compiler
    class << self
      # Registry of compiled method sources: { "ClassName#method" => source_code }
      def registry
        @registry ||= {}
      end

      # Cache directory for generated .rb files
      def cache_dir
        @cache_dir || ".mana_cache"
      end

      attr_writer :cache_dir

      # Get the generated source for a compiled method
      def source(method_name, owner: nil)
        key = registry_key(method_name, owner)
        registry[key]
      end

      # Compile a method: wrap it so first invocation triggers LLM code generation.
      # On subsequent calls, the generated Ruby code is loaded from cache (zero API cost).
      def compile(owner, method_name)
        original = owner.instance_method(method_name)
        compiler = self
        key = registry_key(method_name, owner)

        # Read the prompt from the original method body (the ~"..." string)
        prompt = extract_prompt(original)

        # Build parameter signature for the generated method
        params_desc = describe_params(original)

        # Cache filename based on source file + method name
        source_file = original.source_location&.first
        prompt_hash = Digest::SHA256.hexdigest("#{method_name}:#{params_desc}:#{prompt}")[0, 16]
        cache_path = cache_file_path(method_name, owner, source_file: source_file)

        # Load from cache if file exists and prompt hash matches
        if File.exist?(cache_path)
          first_line = File.open(cache_path, &:readline) rescue ""
          if first_line.include?(prompt_hash)
            cached = File.read(cache_path)
            generated = cached.lines.reject { |l| l.start_with?("#") }.join.strip
            compiler.registry[key] = generated
            v, $VERBOSE = $VERBOSE, nil
            owner.class_eval(generated, cache_path, 1)
            $VERBOSE = v
            return
          end
          # Prompt changed — cache is stale, will regenerate on first call
        end

        # Replace the method with a lazy wrapper that generates code on first call
        old_verbose, $VERBOSE = $VERBOSE, nil
        p_hash = prompt_hash  # capture for closure
        src_file = source_file  # capture for closure
        owner.define_method(method_name) do |*args, **kwargs, &blk|
          # Generate implementation via LLM
          generated = compiler.generate(method_name, params_desc, prompt)

          # Write to cache file for future runs
          cache_path = compiler.write_cache(method_name, generated, owner, prompt_hash: p_hash, source_file: src_file)

          # Store in registry so Mana.source() can retrieve it
          compiler.registry[key] = generated

          # Define the method on the correct owner (not Object) via class_eval
          target_owner = owner
          v, $VERBOSE = $VERBOSE, nil
          target_owner.class_eval(generated, cache_path, 1)
          $VERBOSE = v

          # Call the now-native method (this wrapper never runs again)
          send(method_name, *args, **kwargs, &blk)
        end
        $VERBOSE = old_verbose
      end

      # Generate Ruby method source via LLM.
      # Uses an isolated binding so LLM cannot see Compiler internals.
      def generate(method_name, params_desc, prompt)
        engine_prompt = "Write a Ruby method definition `def #{method_name}(#{params_desc})` that: #{prompt}. " \
                        "Return ONLY the complete method definition (def...end), no explanation. " \
                        "Store the code as a string in <code>"

        # Create isolated binding with only `code` variable visible.
        # Use eval to avoid "assigned but unused variable" parse-time warning.
        isolated = Object.new.instance_eval { eval("code = nil; binding") }
        Mana::Engine.new(isolated).execute(engine_prompt)

        code = isolated.local_variable_get(:code)
        # LLM may return literal \n instead of real newlines — unescape them
        code = code.gsub("\\n", "\n").gsub("\\\"", "\"").gsub("\\'", "'") if code.is_a?(String)
        code
      end

      # Path to the cache file for a method.
      # Includes source file path for uniqueness: lib_foo_calculate.rb
      # Build the cache file path for a method.
      # Prefers source-file-based naming for uniqueness; falls back to owner class name.
      def cache_file_path(method_name, owner = nil, source_file: nil)
        parts = []
        if source_file
          # Convert path relative to pwd: lib/foo.rb -> lib_foo
          rel = source_file.sub("#{Dir.pwd}/", "").sub(/\.rb$/, "")
          parts << rel.tr("/", "_")
        elsif owner && owner != Object
          # Use underscored class name when source file is unavailable
          parts << underscore(owner.name)
        end
        parts << method_name.to_s
        File.join(cache_dir, "#{parts.join('_')}.rb")
      end

      # Write generated code to a cache file, return the path
      def write_cache(method_name, source, owner = nil, prompt_hash: nil, source_file: nil)
        FileUtils.mkdir_p(cache_dir)
        path = cache_file_path(method_name, owner, source_file: source_file)
        header = "# Auto-generated by ruby-mana | prompt_hash: #{prompt_hash}\n# frozen_string_literal: true\n\n"
        File.write(path, "#{header}#{source}\n")
        path
      end

      # Clear all cached files and registry
      def clear!
        FileUtils.rm_rf(cache_dir) if Dir.exist?(cache_dir)
        @registry = {}
      end

      private

      def registry_key(method_name, owner = nil)
        if owner && owner != Object
          "#{owner}##{method_name}"
        else
          method_name.to_s
        end
      end

      # Extract the prompt string from the original method's source code.
      # Two strategies:
      #   1. Read the source file and parse ~"..." (works for .rb files)
      #   2. Disassemble bytecode to find string literal (works for IRB/eval)
      def extract_prompt(unbound_method)
        source_loc = unbound_method.source_location
        return extract_prompt_from_bytecode(unbound_method) unless source_loc

        file, line = source_loc
        return extract_prompt_from_bytecode(unbound_method) unless file && File.exist?(file)

        lines = File.readlines(file)
        # Walk from the def line, tracking block depth to find the matching `end`
        body_lines = []
        depth = 0
        (line - 1...lines.length).each do |i|
          l = lines[i]
          depth += l.scan(/\bdef\b|\bdo\b|\bclass\b|\bmodule\b|\bif\b|\bunless\b|\bcase\b|\bwhile\b|\buntil\b|\bbegin\b/).length
          depth -= l.scan(/\bend\b/).length
          body_lines << l
          break if depth <= 0
        end

        # Extract the prompt string from ~"..." or ~'...' pattern
        body = body_lines.join
        match = body.match(/~"([^"]*)"/) || body.match(/~'([^']*)'/)
        # Fall back to the raw method body (excluding def/end lines) if no pattern found
        match ? match[1] : body_lines[1...-1].join.strip
      end

      # Fallback: extract prompt from method bytecode (works in IRB/eval).
      # Disassembles the method's instruction sequence to find the string literal.
      def extract_prompt_from_bytecode(unbound_method)
        iseq = RubyVM::InstructionSequence.of(unbound_method)
        return nil unless iseq

        # Match putstring or putchilledstring (Ruby 3.4+) instruction
        match = iseq.disasm.match(/put(?:chilled)?string\s+"(.+?)"/)
        match ? match[1] : nil
      rescue
        nil
      end

      # Build a human-readable parameter signature string from method parameters.
      # Maps each parameter type to its Ruby syntax representation.
      def describe_params(unbound_method)
        unbound_method.parameters.map do |(type, name)|
          case type
          when :req then name.to_s            # required positional
          when :opt then "#{name}=nil"         # optional positional
          when :rest then "*#{name}"           # splat
          when :keyreq then "#{name}:"         # required keyword
          when :key then "#{name}: nil"        # optional keyword
          when :keyrest then "**#{name}"       # double splat
          when :block then "&#{name}"          # block parameter
          when :nokey then nil                 # **nil — skip (no keywords accepted)
          else name&.to_s
          end
        end.compact.join(", ")
      end

      def underscore(str)
        return "anonymous" if str.nil? || str.empty?

        str.gsub("::", "_")
           .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
           .gsub(/([a-z\d])([A-Z])/, '\1_\2')
           .downcase
      end
    end
  end
end
