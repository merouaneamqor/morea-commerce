# frozen_string_literal: true

module Types
  class ImageType < BaseObject
    field :id, ID, null: false
    field :filename, String, null: false
    field :url, String, null: false
    field :position, Integer, null: false
  end
end
