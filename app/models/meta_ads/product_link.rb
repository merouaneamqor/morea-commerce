# frozen_string_literal: true

module MetaAds
  # Says which product a Meta campaign, ad set or ad promotes, so the product's profit can include its ad spend.
  # A link made by hand is never replaced by an automatic one.
  class ProductLink < ApplicationRecord
    OBJECT_TYPES = %w[ad ad_set campaign].freeze
    SOURCES = %w[manual auto].freeze

    belongs_to :store
    belongs_to :product
    attr_readonly :store_id, :object_type, :meta_id

    validates :object_type, inclusion: { in: OBJECT_TYPES }
    validates :source, inclusion: { in: SOURCES }
    validates :meta_id, presence: true, format: { with: /\A\d{1,25}\z/ }, uniqueness: { scope: %i[store_id object_type] }
    validate :product_in_same_store

    private

    def product_in_same_store
      errors.add(:product, "must belong to the same store") if product && product.store_id != store_id
    end
  end
end
