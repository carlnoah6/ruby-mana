# frozen_string_literal: true

module Mana
  # Thread-local registry for cross-engine object references.
  #
  # When a complex Ruby object is passed to JS/Python, it gets registered here
  # with a unique integer ID. The foreign engine holds a proxy with that ID and
  # routes method calls back through the bidirectional channel.
  #
  # Thread-local so each engine context (which is also thread-local) has its own
  # isolated set of references.
  class ObjectRegistry
    attr_reader :objects

    def initialize
      @objects = {}
      @next_id = 1
      @release_callbacks = []
    end

    # Store an object and return its reference ID.
    # If the same object is already registered, return the existing ID.
    def register(obj)
      # Check if already registered (by object_id for identity, not equality)
      @objects.each do |id, entry|
        return id if entry[:object].equal?(obj)
      end

      id = @next_id
      @next_id += 1
      @objects[id] = { object: obj, type: obj.class.name }
      id
    end

    # Retrieve an object by its reference ID.
    def get(id)
      entry = @objects[id]
      entry ? entry[:object] : nil
    end

    # Register a callback invoked when any reference is released.
    # The callback receives (id, entry) where entry is { object:, type: }.
    def on_release(&block)
      @release_callbacks << block
    end

    # Release a reference. Returns true if it existed.
    # Fires registered on_release callbacks with the id and entry.
    def release(id)
      entry = @objects.delete(id)
      return false unless entry

      @release_callbacks.each do |cb|
        cb.call(id, entry)
      rescue => e
        # Don't let callback errors break the release
      end
      true
    end

    # Number of live references.
    def size
      @objects.size
    end

    # Remove all references. Fires on_release for each.
    def clear!
      ids = @objects.keys.dup
      ids.each { |id| release(id) }
      @next_id = 1
    end

    # Check if an ID is registered.
    def registered?(id)
      @objects.key?(id)
    end

    # Thread-local singleton access
    def self.current
      Thread.current[:mana_object_registry] ||= new
    end

    def self.reset!
      Thread.current[:mana_object_registry] = nil
    end
  end
end
