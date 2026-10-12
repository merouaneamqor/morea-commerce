# frozen_string_literal: true

module Types
  class VariantKeyInput < BaseInput
    argument :size, String, required: false
    argument :color, String, required: false
  end
end
