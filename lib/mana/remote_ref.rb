# frozen_string_literal: true

module Mana
  # A proxy object representing a remote reference to an object in another engine.
  #
  # When JS or Python receives a complex Ruby object, they get a RemoteRef handle.
  # Method calls on the proxy are routed back to the original object via the
  # ObjectRegistry and the bidirectional calling channel.
  #
  # On the Ruby side, RemoteRef can also wrap foreign objects (JS/Python) that
  # were passed to Ruby — method calls go through the engine's eval mechanism.
  class RemoteRef
    attr_reader :ref_id, :source_engine, :type_name

    def initialize(ref_id, source_engine:, type_name: nil, registry: nil)
      @ref_id = ref_id
      @source_engine = source_engine
      @type_name = type_name
      @registry = registry || ObjectRegistry.current
      setup_release_callback
    end

    # Call a method on the remote object
    def method_missing(name, *args, &block)
      name_s = name.to_s

      # Don't proxy Ruby internal methods
      return super if %w[__id__ __send__ class is_a? kind_of? instance_of? respond_to? respond_to_missing? equal? nil? frozen? tainted? inspect to_s hash].include?(name_s)

      obj = @registry.get(@ref_id)
      raise Mana::Error, "Remote reference #{@ref_id} has been released" unless obj

      obj.public_send(name, *args, &block)
    end

    def respond_to_missing?(name, include_private = false)
      obj = @registry.get(@ref_id)
      return false unless obj
      obj.respond_to?(name, false)
    end

    # Explicitly release this reference
    def release!
      @registry.release(@ref_id)
    end

    # Check if the referenced object is still alive
    def alive?
      @registry.registered?(@ref_id)
    end

    def inspect
      "#<Mana::RemoteRef id=#{@ref_id} engine=#{@source_engine} type=#{@type_name}>"
    end

    def to_s
      obj = @registry.get(@ref_id)
      obj ? obj.to_s : inspect
    end

    private

    # Set up a release callback via Ruby finalizer.
    # When this RemoteRef is garbage collected, the registry entry is released.
    # Uses a class method to avoid capturing `self` in the closure.
    def setup_release_callback
      release_proc = self.class.send(:release_callback, @ref_id, @registry)
      ObjectSpace.define_finalizer(self, release_proc)
    end

    # Build a release proc that doesn't reference the RemoteRef instance.
    # This avoids the "finalizer references object to be finalized" warning.
    def self.release_callback(ref_id, registry)
      proc { |_| registry.release(ref_id) }
    end
    private_class_method :release_callback
  end
end
