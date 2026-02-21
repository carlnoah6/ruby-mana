# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Nested prompts" do
  before do
    Mana.config.api_key = "test-key"
    Thread.current[:mana_memory] = nil
    Thread.current[:mana_incognito] = nil
    Thread.current[:mana_depth] = nil
    @tmpdir = Dir.mktmpdir("mana_test")
    Mana.config.memory_store = Mana::FileStore.new(@tmpdir)
  end

  after do
    Thread.current[:mana_memory] = nil
    Thread.current[:mana_incognito] = nil
    Thread.current[:mana_depth] = nil
    FileUtils.rm_rf(@tmpdir)
    Mana.reset!
  end

  describe "reentrancy" do
    it "allows nested ~\"...\" calls (no reentrancy error)" do
      # Outer call invokes call_func which triggers an inner Engine.run
      # Inner call just does done immediately
      call_count = 0

      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return do
          call_count += 1
          if call_count == 1
            # Outer call: invoke call_func
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "inner_task", "args" => ["hello"] } }]
              })
            }
          elsif call_count == 2
            # Inner call: done immediately
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "inner done" } }]
              })
            }
          else
            # Outer call: done after inner returns
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t3", name: "done", input: { "result" => "outer done" } }]
              })
            }
          end
        end

      def inner_task(msg)
        Mana::Engine.run("inner prompt with #{msg}", binding)
      end

      b = binding
      result = Mana::Engine.run("call inner_task with hello", b)
      expect(result).to eq("outer done")
    end
  end

  describe "memory isolation" do
    it "inner call gets fresh short-term memory" do
      outer_memory = Mana::Memory.current
      outer_memory.short_term << { role: "user", content: "outer context" }
      outer_memory.short_term << { role: "assistant", content: [{ type: "text", text: "outer reply" }] }

      inner_short_term = nil

      # Stub to capture inner memory state
      call_count = 0
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return do |request|
          call_count += 1
          body = JSON.parse(request.body, symbolize_names: true)

          if call_count == 1
            # Outer call: invoke call_func
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "check_inner_memory", "args" => [] } }]
              })
            }
          elsif call_count == 2
            # Inner call: capture messages sent (these come from inner's short-term)
            # The messages array should only contain the inner prompt, not outer context
            inner_short_term = body[:messages]
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "checked" } }]
              })
            }
          else
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t3", name: "done", input: {} }]
              })
            }
          end
        end

      def check_inner_memory
        Mana::Engine.run("inner check", binding)
      end

      b = binding
      Mana::Engine.run("call check_inner_memory", b)

      # Inner call's messages should NOT contain the outer context
      expect(inner_short_term).not_to be_nil
      inner_contents = inner_short_term.select { |m| m[:role] == "user" && m[:content].is_a?(String) }
        .map { |m| m[:content] }
      expect(inner_contents).not_to include("outer context")
      expect(inner_contents).to include("inner check")
    end

    it "inner call shares long-term memory with outer" do
      memory = Mana::Memory.current
      memory.remember("shared fact")

      inner_system_prompt = nil

      call_count = 0
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return do |request|
          call_count += 1
          body = JSON.parse(request.body, symbolize_names: true)

          if call_count == 1
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "check_long_term", "args" => [] } }]
              })
            }
          elsif call_count == 2
            # Capture inner call's system prompt — should contain long-term memory
            inner_system_prompt = body[:system]
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "ok" } }]
              })
            }
          else
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t3", name: "done", input: {} }]
              })
            }
          end
        end

      def check_long_term
        Mana::Engine.run("inner prompt", binding)
      end

      b = binding
      Mana::Engine.run("call check_long_term", b)

      expect(inner_system_prompt).to include("shared fact")
    end

    it "restores outer memory after nested call completes" do
      outer_memory = Mana::Memory.current
      outer_memory.short_term << { role: "user", content: "outer message" }

      call_count = 0
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return do
          call_count += 1
          if call_count == 1
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "nested_call", "args" => [] } }]
              })
            }
          elsif call_count == 2
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "inner" } }]
              })
            }
          else
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t3", name: "done", input: { "result" => "outer" } }]
              })
            }
          end
        end

      def nested_call
        Mana::Engine.run("inner prompt", binding)
      end

      b = binding
      Mana::Engine.run("call nested_call", b)

      # Outer memory should be restored — still the same object
      expect(Mana::Memory.current).to equal(outer_memory)
      # Outer short-term should still contain its original messages (plus new ones from the outer call)
      outer_contents = outer_memory.short_term.select { |m| m[:role] == "user" && m[:content].is_a?(String) }
        .map { |m| m[:content] }
      expect(outer_contents).to include("outer message")
    end
  end

  describe "depth tracking" do
    it "increments and decrements depth correctly" do
      depths = []

      call_count = 0
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return do
          call_count += 1
          depths << Thread.current[:mana_depth]
          if call_count == 1
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "depth_check", "args" => [] } }]
              })
            }
          elsif call_count == 2
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "inner" } }]
              })
            }
          else
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t3", name: "done", input: { "result" => "outer" } }]
              })
            }
          end
        end

      def depth_check
        Mana::Engine.run("inner", binding)
      end

      b = binding
      Mana::Engine.run("call depth_check", b)

      # First API call at depth 1, second at depth 2, third at depth 1 again
      expect(depths).to eq([1, 2, 1])
      # After everything completes, depth should be back to 0
      expect(Thread.current[:mana_depth]).to eq(0)
    end

    it "handles multiple levels of nesting" do
      max_depth = 0

      call_count = 0
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return do
          call_count += 1
          current_depth = Thread.current[:mana_depth]
          max_depth = current_depth if current_depth > max_depth

          if call_count == 1
            # Level 1: call level2_func
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "level2_func", "args" => [] } }]
              })
            }
          elsif call_count == 2
            # Level 2: call level3_func
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t2", name: "call_func", input: { "name" => "level3_func", "args" => [] } }]
              })
            }
          elsif call_count == 3
            # Level 3: done
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t3", name: "done", input: { "result" => "level3" } }]
              })
            }
          elsif call_count == 4
            # Level 2: done
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t4", name: "done", input: { "result" => "level2" } }]
              })
            }
          else
            # Level 1: done
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t5", name: "done", input: { "result" => "level1" } }]
              })
            }
          end
        end

      def level3_func
        Mana::Engine.run("level 3", binding)
      end

      def level2_func
        Mana::Engine.run("level 2", binding)
      end

      b = binding
      result = Mana::Engine.run("level 1", b)

      expect(max_depth).to eq(3)
      expect(result).to eq("level1")
      expect(Thread.current[:mana_depth]).to eq(0)
    end
  end

  describe "lambda support" do
    it "call_func can invoke a lambda defined as a local variable" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(
          # First: call the lambda
          {
            status: 200,
            headers: { "Content-Type" => "application/json" },
            body: JSON.generate({
              content: [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "my_lambda", "args" => ["world"] } }]
            })
          },
          # Second: done
          {
            status: 200,
            headers: { "Content-Type" => "application/json" },
            body: JSON.generate({
              content: [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "final" } }]
            })
          }
        )

      my_lambda = ->(name) { "hello #{name}" }
      b = binding
      result = Mana::Engine.run("call my_lambda", b)
      expect(result).to eq("final")
    end
  end

  describe "compaction" do
    it "does not schedule compaction for nested calls" do
      compaction_called = false
      allow_any_instance_of(Mana::Memory).to receive(:schedule_compaction) do
        compaction_called = true
      end

      call_count = 0
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return do
          call_count += 1
          if call_count == 1
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "nested_func", "args" => [] } }]
              })
            }
          elsif call_count == 2
            # Inner: done — should NOT trigger compaction
            compaction_called = false # reset before inner finishes
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "inner" } }]
              })
            }
          else
            # Outer: done — SHOULD trigger compaction
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t3", name: "done", input: { "result" => "outer" } }]
              })
            }
          end
        end

      def nested_func
        Mana::Engine.run("inner", binding)
      end

      b = binding
      Mana::Engine.run("outer", b)
      # Compaction should have been called for the outer (top-level) call
      expect(compaction_called).to be true
    end
  end

  describe "incognito nesting" do
    it "nested call inside incognito does not create memory" do
      call_count = 0
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return do
          call_count += 1
          if call_count == 1
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t1", name: "call_func", input: { "name" => "incognito_inner", "args" => [] } }]
              })
            }
          elsif call_count == 2
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t2", name: "done", input: { "result" => "inner" } }]
              })
            }
          else
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                content: [{ type: "tool_use", id: "t3", name: "done", input: { "result" => "outer" } }]
              })
            }
          end
        end

      def incognito_inner
        Mana::Engine.run("inner prompt", binding)
      end

      Thread.current[:mana_incognito] = true
      b = binding
      result = Mana::Engine.run("outer incognito", b)
      expect(result).to eq("outer")
      expect(Thread.current[:mana_depth]).to eq(0)
    end
  end
end
