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

    # Release a reference. Returns true if it existed.
    def release(id)
      !!@objects.delete(id)
    end

    # Number of live references.
    def size
      @objects.size
    end

    # Remove all references.
    def clear!
      @objects.clear
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
      registry = Thread.current[:mana_object_registry]
      registry&.clear!
      Thread.current[:mana_object_registry] = nil
    end
  end
end
