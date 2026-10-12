# frozen_string_literal: true

module Mutations
  class DeleteCollection < BaseMutation
    argument :slug, String, required: true
    argument :confirm, Boolean, required: true

    field :deleted, Boolean, null: false
    field :errors, [ String ], null: false

    def resolve(slug:, confirm:)
      return { deleted: false, errors: [ "Set confirm: true to delete." ] } unless confirm

      collection = store.collections.find_by(slug: slug)
      return { deleted: false, errors: [ "Collection not found: #{slug}" ] } unless collection

      collection.destroy!
      { deleted: true, errors: [] }
    end
  end
end
