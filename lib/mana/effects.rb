# frozen_string_literal: true

module Mana
  module Effects
    ReadVar   = Struct.new(:name)
    WriteVar  = Struct.new(:name, :value)
    ReadAttr  = Struct.new(:obj_name, :attr)
    WriteAttr = Struct.new(:obj_name, :attr, :value)
    CallFunc  = Struct.new(:name, :args)
    Done      = Struct.new(:result)
  end
end
