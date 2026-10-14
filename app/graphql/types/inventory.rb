# frozen_string_literal: true

module Types
  module Inventory
    class MovementType < BaseObject
      field :id, ID, null: false
      field :product_slug, String, null: false
      field :product_name, String, null: false
      field :size, String, null: true
      field :color, String, null: true
      field :variant_name, String, null: true
      field :order_number, String, null: true
      field :quantity, Integer, null: false
      field :reason, String, null: false
      field :note, String, null: true
      field :stock_after, Integer, null: true
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false

      def product_slug
        object.product.slug
      end

      def product_name
        object.product.name
      end

      def size
        object.product_variant&.size_value
      end

      def color
        object.product_variant&.color_value
      end

      def variant_name
        object.product_variant&.display_name
      end

      def order_number
        object.order&.number
      end

      def stock_after
        target = object.product_variant || object.product
        target&.stock
      end
    end

    class LevelType < BaseObject
      field :slug, String, null: false
      field :name, String, null: false
      field :status, String, null: false
      field :track_inventory, Boolean, null: false
      field :sku, String, null: true
      field :size, String, null: true
      field :color, String, null: true
      field :variant_id, ID, null: true
      field :stock, Integer, null: true
      field :sellable_stock, Integer, null: true
      field :low_stock, Boolean, null: false
      field :stock_value_dh, Integer, null: true
      field :price_dh, Integer, null: false
    end

    class ReasonCountType < BaseObject
      field :reason, String, null: false
      field :count, Integer, null: false
      field :quantity, Integer, null: false
    end

    class SummaryType < BaseObject
      field :tracked_products, Integer, null: false
      field :untracked_products, Integer, null: false
      field :low_stock_count, Integer, null: false
      field :out_of_stock_count, Integer, null: false
      field :total_units, Integer, null: false
      field :total_stock_value_dh, Integer, null: false
      field :threshold, Integer, null: false
      field :by_reason, [ ReasonCountType ], null: false
    end
  end
end
