# frozen_string_literal: true

module Types
  class VariantInput < BaseInput
    argument :size, String, required: false
    argument :color, String, required: false
    argument :color_hex, String, required: false
    argument :sku, String, required: false
    argument :stock, Integer, required: false
    argument :active, Boolean, required: false
    argument :price_dh, Integer, required: false
  end
end
