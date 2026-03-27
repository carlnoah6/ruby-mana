# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::Chat do
  # Access private class methods for testing
  def render_markdown_inline(text)
    described_class.send(:render_markdown_inline, text)
  end

  def render_line(line, in_code_block)
    described_class.send(:render_line, line, in_code_block)
  end

  def render_markdown(text)
    described_class.send(:render_markdown, text)
  end

  def flush_line_buffer(buffer, in_code_block)
    described_class.send(:flush_line_buffer, buffer, in_code_block)
  end

  def format_tool_call(name, input)
    described_class.send(:format_tool_call, name, input)
  end

  def truncate(str, max)
    described_class.send(:truncate, str, max)
  end

  def ruby_syntax?(input)
    described_class.send(:ruby_syntax?, input)
  end

  def incomplete_ruby?(code)
    described_class.send(:incomplete_ruby?, code)
  end

  def eval_ruby(bnd, code, &block)
    described_class.send(:eval_ruby, bnd, code, &block)
  end

  describe "render_markdown_inline" do
    it "renders **bold** as ANSI bold" do
      result = render_markdown_inline("hello **world**")
      expect(result).to include("\e[1m")
      expect(result).to include("world")
    end

    it "renders `code` as ANSI cyan" do
      result = render_markdown_inline("use `Array#map`")
      expect(result).to include("\e[36m")
      expect(result).to include("Array#map")
    end

    it "renders # headings as bold" do
      result = render_markdown_inline("# Hello")
      expect(result).to include("\e[1m")
      expect(result).to include("Hello")
    end

    it "leaves plain text unchanged" do
      expect(render_markdown_inline("plain text")).to eq("plain text")
    end
  end

  describe "render_line" do
    it "starts code block on ```" do
      result = capture_output { render_line("```ruby", false) }
      expect(result[:state]).to be true
    end

    it "ends code block on ```" do
      result = capture_output { render_line("```", true) }
      expect(result[:state]).to be false
    end

    it "renders code block lines with code color" do
      result = capture_output { render_line("  x = 1", true) }
      expect(result[:output]).to include("\e[36m")
    end

    it "renders normal lines with markdown" do
      result = capture_output { render_line("hello **world**", false) }
      expect(result[:output]).to include("world")
    end
  end

  describe "render_markdown" do
    it "renders a complete markdown block" do
      text = "# Title\n\nHello **world**\n\n```ruby\nx = 1\n```\n\nDone."
      result = render_markdown(text)
      expect(result).to include("Title")
      expect(result).to include("world")
      expect(result).to include("x = 1")
      expect(result).to include("Done")
    end

    it "handles text without code blocks" do
      result = render_markdown("just **text**")
      expect(result).to include("text")
    end
  end

  describe "flush_line_buffer" do
    it "prints and clears the buffer" do
      buffer = +"hello"
      output = capture_print { flush_line_buffer(buffer, false) }
      expect(output).to include("hello")
      expect(buffer).to be_empty
    end

    it "does nothing for empty buffer" do
      buffer = +""
      output = capture_print { flush_line_buffer(buffer, false) }
      expect(output).to eq("")
    end

    it "applies code color inside code block" do
      buffer = +"x = 1"
      output = capture_print { flush_line_buffer(buffer, true) }
      expect(output).to include("\e[36m")
    end
  end

  describe "format_tool_call" do
    it "formats call_func with args" do
      result = format_tool_call("call_func", { "name" => "double", "args" => [21] })
      expect(result).to eq("double(21)")
    end

    it "formats call_func with body" do
      result = format_tool_call("call_func", { "name" => "map", "args" => [], "body" => "|x| x * 2" })
      expect(result).to include("map")
      expect(result).to include("|x| x * 2")
    end

    it "formats read_var" do
      result = format_tool_call("read_var", { "name" => "x" })
      expect(result).to eq("x")
    end

    it "formats write_var" do
      result = format_tool_call("write_var", { "name" => "x", "value" => 42 })
      expect(result).to eq("x = 42")
    end

    it "formats read_attr" do
      result = format_tool_call("read_attr", { "obj" => "user", "attr" => "name" })
      expect(result).to eq("user.name")
    end

    it "formats remember" do
      result = format_tool_call("remember", { "content" => "user likes Ruby" })
      expect(result).to eq("remember: user likes Ruby")
    end

    it "formats knowledge" do
      result = format_tool_call("knowledge", { "topic" => "Array#map" })
      expect(result).to eq("knowledge(Array#map)")
    end

    it "formats unknown tools" do
      result = format_tool_call("done", {})
      expect(result).to eq("done")
    end
  end

  describe "truncate" do
    it "leaves short strings alone" do
      expect(truncate("hello", 10)).to eq("hello")
    end

    it "truncates long strings" do
      result = truncate("a" * 100, 10)
      expect(result.length).to eq(13) # 10 + "..."
      expect(result).to end_with("...")
    end
  end

  describe "ruby_syntax?" do
    it "detects valid Ruby" do
      expect(ruby_syntax?("x = 1 + 2")).to be true
    end

    it "detects method calls" do
      expect(ruby_syntax?("[1,2,3].map { |x| x * 2 }")).to be true
    end

    it "rejects obvious syntax errors" do
      expect(ruby_syntax?("def end def")).to be false
    end
  end

  describe "incomplete_ruby?" do
    it "returns true for unclosed block" do
      expect(incomplete_ruby?("def foo")).to be true
    end

    it "returns true for unclosed string" do
      expect(incomplete_ruby?('"hello')).to be true
    end

    it "returns false for complete code" do
      expect(incomplete_ruby?("x = 1")).to be false
    end

    it "returns false for invalid syntax" do
      expect(incomplete_ruby?("1 +* 2")).to be false
    end
  end

  describe "eval_ruby" do
    it "evaluates Ruby code in binding" do
      b = binding
      output = capture_print { eval_ruby(b, "1 + 2") }
      expect(output).to include("3")
    end

    it "yields to fallback on NameError" do
      b = binding
      fallback_called = false
      capture_print { eval_ruby(b, "nonexistent_var_xyz") { fallback_called = true } }
      expect(fallback_called).to be true
    end

    it "prints error without fallback on NameError" do
      b = binding
      output = capture_print { eval_ruby(b, "nonexistent_var_xyz") }
      expect(output).to include("NameError")
    end

    it "prints error for other exceptions" do
      b = binding
      output = capture_print { eval_ruby(b, "1 / 0") }
      expect(output).to include("ZeroDivisionError")
    end
  end

  private

  # Capture $stdout print output
  def capture_print
    output = +""
    allow($stdout).to receive(:write) { |s| output << s }
    allow($stdout).to receive(:puts) { |*args| output << args.join("\n") << "\n" }
    yield
    output
  end

  # Capture output + return value from render_line
  def capture_output
    output = +""
    allow($stdout).to receive(:write) { |s| output << s }
    allow($stdout).to receive(:print) { |*args| output << args.join }
    state = yield
    { output: output, state: state }
  end
end
