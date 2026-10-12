# frozen_string_literal: true

module Types
  class CollectionTranslationInput < BaseInput
    argument :locale, String, required: true
    argument :name, String, required: false
    argument :subtitle, String, required: false
    argument :description, String, required: false
  end
end
