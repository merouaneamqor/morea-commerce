# frozen_string_literal: true

module Mutations
  class DeleteProduct < BaseMutation
    argument :slug, String, required: true
    argument :confirm, Boolean, required: true

    field :deleted, Boolean, null: false
    field :errors, [ String ], null: false

    def resolve(slug:, confirm:)
      return { deleted: false, errors: [ "Set confirm: true to delete." ] } unless confirm

      product = store.products.find_by(slug: slug)
      return { deleted: false, errors: [ "Product not found: #{slug}" ] } unless product

      product.destroy!
      { deleted: true, errors: [] }
    rescue ActiveRecord::DeleteRestrictionError
      { deleted: false, errors: [ "Product is on existing orders and cannot be deleted." ] }
    end
  end
end
