# frozen_string_literal: true

module Mutations
  class AdjustStock < BaseMutation
    description "Apply a signed stock delta and write an inventory movement. Prefer this over setting stock absolutely when tracking inventory."

    argument :slug, String, required: true
    argument :quantity, Integer, required: true
    argument :reason, String, required: true
    argument :note, String, required: false
    argument :size, String, required: false
    argument :color, String, required: false
    argument :variant_id, ID, required: false

    field :product, Types::ProductType, null: true
    field :movement, Types::Inventory::MovementType, null: true
    field :previous_stock, Integer, null: true
    field :stock, Integer, null: true
    field :errors, [ String ], null: false

    def resolve(slug:, quantity:, reason:, note: nil, size: nil, color: nil, variant_id: nil)
      result = Catalog::Inventory.adjust!(
        store,
        slug: slug,
        quantity: quantity,
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
