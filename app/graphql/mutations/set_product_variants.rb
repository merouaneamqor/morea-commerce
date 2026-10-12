# frozen_string_literal: true

module Mutations
  class SetProductVariants < BaseMutation
    argument :slug, String, required: true
    argument :variants, [ Types::VariantInput ], required: true

    field :product, Types::ProductType, null: true
    field :errors, [ String ], null: false

    def resolve(slug:, variants:)
      product = store.products.find_by(slug: slug)
      return failure("Product not found: #{slug}").merge(product: nil) unless product

      Catalog::Variants.upsert!(product, variants)
      { product: product, errors: [] }
    rescue Catalog::Variants::Error, ActiveRecord::RecordInvalid => e
      message = e.is_a?(ActiveRecord::RecordInvalid) ? e.record.errors.full_messages.to_sentence : e.message
      failure(message).merge(product: nil)
    end
  end
end
