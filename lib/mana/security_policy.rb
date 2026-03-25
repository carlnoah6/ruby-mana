# frozen_string_literal: true

require "set"

module Mana
  # Configurable security policy for LLM tool calls.
  #
  # Five levels (higher = more permissions, each includes all below):
  #   0 :sandbox    — variables and user functions only
  #   1 :strict     — + safe stdlib (Time, Date, Math) [default]
  #   2 :standard   — + read filesystem (File.read, Dir.glob)
  #   3 :permissive — + write files, network, require
  #   4 :danger     — no restrictions
  #
  # Usage:
  #   Mana.configure { |c| c.security = :standard }
  #   Mana.configure { |c| c.security = 2 }
  #   Mana.configure do |c|
  #     c.security = :strict
  #     c.security_policy.allow_receiver "File", only: %w[read exist?]
  #   end
  class SecurityPolicy
    LEVELS = { sandbox: 0, strict: 1, standard: 2, permissive: 3, danger: 4 }.freeze

    # Methods blocked at each level. Higher levels remove restrictions.
    PRESETS = {
      sandbox: {
        blocked_methods: %w[
          methods singleton_methods private_methods protected_methods public_methods
          instance_variables instance_variable_get instance_variable_set remove_instance_variable
          local_variables global_variables
          send __send__ public_send eval instance_eval instance_exec class_eval module_eval
          system exec fork spawn ` require require_relative load
          exit exit! abort at_exit
        ],
        blocked_receivers: :all
      },
      strict: {
        blocked_methods: %w[
          methods singleton_methods private_methods protected_methods public_methods
          instance_variables instance_variable_get instance_variable_set remove_instance_variable
          local_variables global_variables
          send __send__ public_send eval instance_eval instance_exec class_eval module_eval
          system exec fork spawn ` require require_relative load
          exit exit! abort at_exit
        ],
        blocked_receivers: {
          "File" => :all, "Dir" => :all, "IO" => :all,
          "Kernel" => :all, "Process" => :all, "ObjectSpace" => :all, "ENV" => :all
        }
      },
      standard: {
        blocked_methods: %w[
          methods singleton_methods private_methods protected_methods public_methods
          instance_variables instance_variable_get instance_variable_set remove_instance_variable
          local_variables global_variables
          send __send__ public_send eval instance_eval instance_exec class_eval module_eval
          system exec fork spawn `
          exit exit! abort at_exit
          require require_relative load
        ],
        blocked_receivers: {
          "File" => Set.new(%w[delete write open chmod chown rename unlink]),
          "Dir" => Set.new(%w[delete rmdir mkdir chdir]),
          "IO" => :all, "Kernel" => :all, "Process" => :all,
          "ObjectSpace" => :all, "ENV" => :all
        }
      },
      permissive: {
        blocked_methods: %w[
          eval instance_eval instance_exec class_eval module_eval
          system exec fork spawn `
          exit exit! abort at_exit
        ],
        blocked_receivers: {
          "ObjectSpace" => :all
        }
      },
      danger: {
        blocked_methods: [],
        blocked_receivers: {}
      }
    }.freeze

    attr_reader :preset

    # Initialize security policy from a preset name (Symbol) or numeric level (Integer)
    def initialize(preset = :strict)
      # Convert numeric level to its corresponding symbol name
      preset = LEVELS.key(preset) if preset.is_a?(Integer)
      raise ArgumentError, "unknown security level: #{preset.inspect}. Use: #{LEVELS.keys.join(', ')}" unless PRESETS.key?(preset)

      @preset = preset
      data = PRESETS[preset]
      @blocked_methods = Set.new(data[:blocked_methods])

      if data[:blocked_receivers] == :all
        # Sandbox mode: block all receiver calls by default
        @block_all_receivers = true
        @blocked_receivers = {}
      else
        # Other modes: block only specific methods on specific receivers
        @block_all_receivers = false
        @blocked_receivers = data[:blocked_receivers].transform_values { |v|
          v == :all ? :all : Set.new(v)
        }
      end

      # Allowlist overrides added via allow_receiver(name, only: [...])
      @allowed_overrides = {}
      yield self if block_given?
    end

    # --- Mutators ---

    def allow_method(name)
      @blocked_methods.delete(name.to_s)
    end

    def block_method(name)
      @blocked_methods.add(name.to_s)
    end

    # Allow a receiver's calls. With `only:`, allowlist specific methods;
    # without it, fully unblock the receiver.
    def allow_receiver(name, only: nil)
      name = name.to_s
      if only
        # Allowlist only the specified methods (override takes priority over block rules)
        @allowed_overrides[name] = Set.new(only.map(&:to_s))
      else
        # Fully unblock the receiver and remove any override
        @blocked_receivers.delete(name)
        @allowed_overrides.delete(name)
      end
    end

    # Block a receiver's calls. With `only:`, block specific methods;
    # without it, block all methods on the receiver.
    def block_receiver(name, only: nil)
      name = name.to_s
      if only
        existing = @blocked_receivers[name]
        if existing == :all
          # Already fully blocked — nothing to add
        elsif existing.is_a?(Set)
          # Merge new blocked methods into the existing set
          existing.merge(only.map(&:to_s))
        else
          # First partial block rule for this receiver
          @blocked_receivers[name] = Set.new(only.map(&:to_s))
        end
      else
        # Block all methods on this receiver
        @blocked_receivers[name] = :all
        @allowed_overrides.delete(name)
      end
    end

    # --- Queries ---

    def method_blocked?(name)
      @blocked_methods.include?(name.to_s)
    end

    # Check whether calling `method` on `receiver` is blocked by the policy
    def receiver_call_blocked?(receiver, method)
      # Danger mode has no restrictions at all
      return false if @preset == :danger

      r, m = receiver.to_s, method.to_s

      # Sandbox mode: block everything unless explicitly allowlisted
      if @block_all_receivers
        return !(@allowed_overrides.key?(r) && @allowed_overrides[r].include?(m))
      end

      # Receiver not in the block list — allow
      rule = @blocked_receivers[r]
      return false if rule.nil?

      # Allowlist override takes priority: if user explicitly allowed this method, pass
      if @allowed_overrides.key?(r) && @allowed_overrides[r].include?(m)
        return false
      end

      # Blocked if receiver is fully blocked (:all) or method is in the blocked set
      rule == :all || rule.include?(m)
    end

    def level
      LEVELS[@preset]
    end
  end
end
