# frozen_string_literal: true

module Types
  class ProductTranslationInput < BaseInput
    argument :locale, String, required: true
    argument :name, String, required: false
    argument :short_description, String, required: false
    argument :story, String, required: false
    argument :material, String, required: false
    argument :fit, String, required: false
    argument :movement, String, required: false
    argument :dimensions, String, required: false
    argument :origin, String, required: false
    argument :care, String, required: false
    argument :seo_title, String, required: false
    argument :seo_description, String, required: false
  end
end
