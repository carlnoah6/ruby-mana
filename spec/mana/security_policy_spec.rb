# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::SecurityPolicy do
  describe "initialization" do
    it "defaults to :strict" do
      policy = described_class.new
      expect(policy.preset).to eq(:strict)
      expect(policy.level).to eq(1)
    end

    it "accepts symbol preset" do
      policy = described_class.new(:permissive)
      expect(policy.preset).to eq(:permissive)
      expect(policy.level).to eq(3)
    end

    it "accepts integer level" do
      policy = described_class.new(2)
      expect(policy.preset).to eq(:standard)
      expect(policy.level).to eq(2)
    end

    it "raises on unknown preset" do
      expect { described_class.new(:unknown) }.to raise_error(ArgumentError, /unknown security level/)
    end

    it "accepts a block for fine-tuning" do
      policy = described_class.new(:strict) do |p|
        p.allow_receiver "File", only: %w[read]
      end
      expect(policy.receiver_call_blocked?("File", "read")).to be false
      expect(policy.receiver_call_blocked?("File", "delete")).to be true
    end
  end

  describe "levels" do
    it "sandbox (0) blocks all receiver calls" do
      policy = described_class.new(:sandbox)
      expect(policy.receiver_call_blocked?("Time", "now")).to be true
      expect(policy.receiver_call_blocked?("File", "read")).to be true
      expect(policy.method_blocked?("eval")).to be true
      expect(policy.method_blocked?("system")).to be true
    end

    it "strict (1) allows safe stdlib but blocks filesystem" do
      policy = described_class.new(:strict)
      expect(policy.receiver_call_blocked?("Time", "now")).to be false
      expect(policy.receiver_call_blocked?("Date", "today")).to be false
      expect(policy.receiver_call_blocked?("Math", "sqrt")).to be false
      expect(policy.receiver_call_blocked?("File", "read")).to be true
      expect(policy.receiver_call_blocked?("Dir", "glob")).to be true
      expect(policy.method_blocked?("eval")).to be true
      expect(policy.method_blocked?("system")).to be true
    end

    it "standard (2) allows read-only filesystem" do
      policy = described_class.new(:standard)
      expect(policy.receiver_call_blocked?("File", "read")).to be false
      expect(policy.receiver_call_blocked?("File", "exist?")).to be false
      expect(policy.receiver_call_blocked?("File", "delete")).to be true
      expect(policy.receiver_call_blocked?("File", "write")).to be true
      expect(policy.receiver_call_blocked?("Dir", "glob")).to be false
      expect(policy.receiver_call_blocked?("Dir", "delete")).to be true
      expect(policy.receiver_call_blocked?("IO", "popen")).to be true
      expect(policy.method_blocked?("eval")).to be true
    end

    it "permissive (3) only blocks eval/exec/fork" do
      policy = described_class.new(:permissive)
      expect(policy.receiver_call_blocked?("File", "read")).to be false
      expect(policy.receiver_call_blocked?("File", "write")).to be false
      expect(policy.receiver_call_blocked?("Net::HTTP", "get")).to be false
      expect(policy.method_blocked?("eval")).to be true
      expect(policy.method_blocked?("system")).to be true
      expect(policy.method_blocked?("require")).to be false
    end

    it "danger (4) blocks nothing" do
      policy = described_class.new(:danger)
      expect(policy.receiver_call_blocked?("File", "delete")).to be false
      expect(policy.receiver_call_blocked?("IO", "popen")).to be false
      expect(policy.receiver_call_blocked?("ObjectSpace", "each_object")).to be false
      expect(policy.method_blocked?("eval")).to be false
      expect(policy.method_blocked?("system")).to be false
    end
  end

  describe "#allow_method / #block_method" do
    it "allows a previously blocked method" do
      policy = described_class.new(:strict)
      expect(policy.method_blocked?("require")).to be true
      policy.allow_method("require")
      expect(policy.method_blocked?("require")).to be false
    end

    it "blocks an additional method" do
      policy = described_class.new(:strict)
      expect(policy.method_blocked?("puts")).to be false
      policy.block_method("puts")
      expect(policy.method_blocked?("puts")).to be true
    end
  end

  describe "#allow_receiver / #block_receiver" do
    it "allows specific methods on a blocked receiver" do
      policy = described_class.new(:strict)
      policy.allow_receiver "File", only: %w[read exist? basename]
      expect(policy.receiver_call_blocked?("File", "read")).to be false
      expect(policy.receiver_call_blocked?("File", "exist?")).to be false
      expect(policy.receiver_call_blocked?("File", "delete")).to be true
    end

    it "fully unblocks a receiver without only:" do
      policy = described_class.new(:strict)
      policy.allow_receiver "File"
      expect(policy.receiver_call_blocked?("File", "read")).to be false
      expect(policy.receiver_call_blocked?("File", "delete")).to be false
    end

    it "blocks a new receiver entirely" do
      policy = described_class.new(:permissive)
      policy.block_receiver "Net::HTTP"
      expect(policy.receiver_call_blocked?("Net::HTTP", "get")).to be true
    end

    it "blocks specific methods on a receiver" do
      policy = described_class.new(:permissive)
      policy.block_receiver "File", only: %w[delete chmod]
      expect(policy.receiver_call_blocked?("File", "delete")).to be true
      expect(policy.receiver_call_blocked?("File", "chmod")).to be true
      expect(policy.receiver_call_blocked?("File", "read")).to be false
    end
  end

  describe "config integration" do
    before { Mana.reset! }

    it "defaults to standard" do
      expect(Mana.config.security_policy.preset).to eq(:standard)
    end

    it "sets by symbol" do
      Mana.configure { |c| c.security = :permissive }
      expect(Mana.config.security_policy.preset).to eq(:permissive)
      expect(Mana.config.security_policy.level).to eq(3)
    end

    it "sets by integer" do
      Mana.configure { |c| c.security = 0 }
      expect(Mana.config.security_policy.preset).to eq(:sandbox)
    end

    it "sets by policy instance" do
      policy = described_class.new(:standard) { |p| p.allow_receiver "File", only: %w[read] }
      Mana.configure { |c| c.security = policy }
      expect(Mana.config.security_policy.preset).to eq(:standard)
      expect(Mana.config.security_policy.receiver_call_blocked?("File", "read")).to be false
    end
  end

  describe "allow + block interaction on same receiver" do
    it "allow_receiver overrides block_receiver for specific methods" do
      policy = described_class.new(:strict)
      # File is fully blocked in :strict
      expect(policy.receiver_call_blocked?("File", "read")).to be true
      # Allow only read
      policy.allow_receiver "File", only: %w[read]
      expect(policy.receiver_call_blocked?("File", "read")).to be false
      expect(policy.receiver_call_blocked?("File", "delete")).to be true
    end

    it "block_receiver after allow_receiver re-blocks the receiver" do
      policy = described_class.new(:permissive)
      # File is not blocked in :permissive
      expect(policy.receiver_call_blocked?("File", "read")).to be false
      # Block it
      policy.block_receiver "File"
      expect(policy.receiver_call_blocked?("File", "read")).to be true
      # Allow override no longer applies after full block
      expect(policy.receiver_call_blocked?("File", "delete")).to be true
    end

    it "partial block then partial allow on same receiver" do
      policy = described_class.new(:permissive)
      policy.block_receiver "File", only: %w[delete write]
      policy.allow_receiver "File", only: %w[write]
      # delete is blocked, write is allowed via override
      expect(policy.receiver_call_blocked?("File", "delete")).to be true
      expect(policy.receiver_call_blocked?("File", "write")).to be false
      expect(policy.receiver_call_blocked?("File", "read")).to be false
    end
  end

  describe "sandbox mode with overrides" do
    it "allows explicitly allowlisted receiver in sandbox" do
      policy = described_class.new(:sandbox)
      policy.allow_receiver "Time", only: %w[now]
      expect(policy.receiver_call_blocked?("Time", "now")).to be false
      expect(policy.receiver_call_blocked?("Time", "parse")).to be true
    end
  end
end
