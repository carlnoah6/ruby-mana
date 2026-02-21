# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mana::FileStore do
  before do
    @tmpdir = Dir.mktmpdir("mana_store_test")
    @store = described_class.new(@tmpdir)
  end

  after { FileUtils.rm_rf(@tmpdir) }

  describe "#read" do
    it "returns empty array when file doesn't exist" do
      expect(@store.read("nonexistent")).to eq([])
    end

    it "reads persisted memories" do
      memories = [{ id: 1, content: "test", created_at: "2026-01-01T00:00:00+00:00" }]
      @store.write("test-ns", memories)

      result = @store.read("test-ns")
      expect(result.size).to eq(1)
      expect(result.first[:content]).to eq("test")
    end

    it "handles corrupted JSON gracefully" do
      path = File.join(@tmpdir, "memory", "broken.json")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "not json")

      expect(@store.read("broken")).to eq([])
    end
  end

  describe "#write" do
    it "creates directories if needed" do
      @store.write("deep-ns", [{ id: 1, content: "test" }])
      expect(File.exist?(File.join(@tmpdir, "memory", "deep-ns.json"))).to be true
    end

    it "overwrites existing file" do
      @store.write("ns", [{ id: 1, content: "first" }])
      @store.write("ns", [{ id: 1, content: "second" }])

      result = @store.read("ns")
      expect(result.size).to eq(1)
      expect(result.first[:content]).to eq("second")
    end
  end

  describe "#clear" do
    it "deletes the namespace file" do
      @store.write("to-clear", [{ id: 1, content: "test" }])
      @store.clear("to-clear")

      expect(@store.read("to-clear")).to eq([])
    end

    it "does nothing for non-existent namespace" do
      expect { @store.clear("nonexistent") }.not_to raise_error
    end
  end
end

RSpec.describe Mana::MemoryStore do
  describe "abstract interface" do
    it "raises NotImplementedError for read" do
      expect { described_class.new.read("ns") }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for write" do
      expect { described_class.new.write("ns", []) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for clear" do
      expect { described_class.new.clear("ns") }.to raise_error(NotImplementedError)
    end
  end
end
