# frozen_string_literal: true

module Mutations
  class SetStock < BaseMutation
    description "Set absolute on-hand stock and write a ledger movement for the delta. Default reason is correction."

    argument :slug, String, required: true
    argument :stock, Integer, required: true
    argument :reason, String, required: false
    argument :note, String, required: false
    argument :size, String, required: false
    argument :color, String, required: false
    argument :variant_id, ID, required: false

    field :product, Types::ProductType, null: true
    field :movement, Types::Inventory::MovementType, null: true
    field :previous_stock, Integer, null: true
    field :stock, Integer, null: true
    field :errors, [ String ], null: false

    def resolve(slug:, stock:, reason: nil, note: nil, size: nil, color: nil, variant_id: nil)
      result = Catalog::Inventory.set!(
        store,
        slug: slug,
        stock: stock,
        reason: reason,
        note: note,
        size: size,
        color: color,
        variant_id: variant_id
      )
      {
        product: result.product,
        movement: result.movement,
        previous_stock: result.previous_stock,
        stock: result.stock,
        errors: []
      }
    rescue Catalog::Inventory::Error => e
      failure(e.message).merge(product: nil, movement: nil, previous_stock: nil, stock: nil)
    end
  end
end
