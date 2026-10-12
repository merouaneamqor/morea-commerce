# frozen_string_literal: true

module Types
  class ProductTranslationType < BaseObject
    field :locale, String, null: false
    field :name, String, null: true
    field :short_description, String, null: true
    field :story, String, null: true
    field :material, String, null: true
    field :fit, String, null: true
    field :movement, String, null: true
    field :dimensions, String, null: true
    field :origin, String, null: true
    field :care, String, null: true
    field :seo_title, String, null: true
    field :seo_description, String, null: true
  end
end
