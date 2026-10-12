# frozen_string_literal: true

module Types
  class CollectionTranslationType < BaseObject
    field :locale, String, null: false
    field :name, String, null: true
    field :subtitle, String, null: true
    field :description, String, null: true
  end
end
