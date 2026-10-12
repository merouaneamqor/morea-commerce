# frozen_string_literal: true

module Types
  module Analytics
    class StatusCountType < BaseObject
      field :status, String, null: false
      field :count, Integer, null: false
    end

    class CityStatType < BaseObject
      field :city, String, null: false
      field :orders, Integer, null: false
      field :delivered, Integer, null: false
      field :delivery_rate, Float, null: false
      field :revenue_dh, Integer, null: false
    end

    class DayStatType < BaseObject
      field :date, GraphQL::Types::ISO8601Date, null: false
      field :placed, Integer, null: false
      field :delivered, Integer, null: false
      field :revenue_dh, Integer, null: false
    end

    class StoreStatsType < BaseObject
      field :from, GraphQL::Types::ISO8601Date, null: false
      field :to, GraphQL::Types::ISO8601Date, null: false
      field :placed_count, Integer, null: false
      field :placed_revenue_dh, Integer, null: false
      field :shipping_dh, Integer, null: false
      field :discount_dh, Integer, null: false
      field :average_order_dh, Integer, null: false
      field :delivered_count, Integer, null: false
      field :delivered_revenue_dh, Integer, null: false
      field :delivery_rate, Float, null: false
      field :cancel_rate, Float, null: false
      field :return_rate, Float, null: false
      field :by_status, [ StatusCountType ], null: false
      field :pipeline, [ StatusCountType ], null: false
      field :by_city, [ CityStatType ], null: false
      field :by_day, [ DayStatType ], null: false
    end

    class VariantStatType < BaseObject
      field :name, String, null: false
      field :units_placed, Integer, null: false
      field :units_delivered, Integer, null: false
      field :stock, Integer, null: true
    end

    class ProductStatType < BaseObject
      field :slug, String, null: false
      field :name, String, null: false
      field :status, String, null: false
      field :price_dh, Integer, null: false
      field :stock, Integer, null: true
      field :stock_value_dh, Integer, null: true
      field :low_stock, Boolean, null: false
      field :units_placed, Integer, null: false
      field :units_delivered, Integer, null: false
      field :units_cancelled, Integer, null: false
      field :units_returned, Integer, null: false
      field :revenue_placed_dh, Integer, null: false
      field :revenue_delivered_dh, Integer, null: false
      field :orders, Integer, null: false
      field :variants, [ VariantStatType ], null: false
    end

    class OrderItemType < BaseObject
      field :product_slug, String, null: false
      field :product_name, String, null: false
      field :variant_name, String, null: true
      field :quantity, Integer, null: false
      field :unit_price_dh, Integer, null: false
      field :total_dh, Integer, null: false

      def product_slug
        object.product.slug
      end

      def unit_price_dh
        object.unit_price_cents / 100
      end

      def total_dh
        object.total_cents / 100
      end
    end

    class SenditType < BaseObject
      field :code, String, null: true
      field :status, String, null: true
      field :fee_dh, Integer, null: true
      field :deliver_by, GraphQL::Types::ISO8601Date, null: true
      field :error, String, null: true

      def code
        object.sendit_code
      end

      def status
        object.sendit_status
      end

      def fee_dh
        object.sendit_fee&.round
      end

      def deliver_by
        object.sendit_deliver_by
      end

      def error
        object.sendit_error
      end
    end

    class OrderType < BaseObject
      field :number, String, null: false
      field :status, String, null: false
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :confirmed_at, GraphQL::Types::ISO8601DateTime, null: true
      field :shipped_at, GraphQL::Types::ISO8601DateTime, null: true
      field :delivered_at, GraphQL::Types::ISO8601DateTime, null: true
      field :cancelled_at, GraphQL::Types::ISO8601DateTime, null: true
      field :returned_at, GraphQL::Types::ISO8601DateTime, null: true
      field :city, String, null: false
      field :district, String, null: true
      field :subtotal_dh, Integer, null: false
      field :shipping_dh, Integer, null: false
      field :discount_dh, Integer, null: false
      field :total_dh, Integer, null: false
      field :discount_code, String, null: true
      field :notes, String, null: true
      field :sendit, SenditType, null: false
      field :items, [ OrderItemType ], null: false

      def city
        object.customer_city
      end

      def district
        object.customer_district.presence || object.sendit_district_name
      end

      def subtotal_dh
        object.subtotal_cents / 100
      end

      def shipping_dh
        object.shipping_cents / 100
      end

      def discount_dh
        object.discount_cents / 100
      end

      def total_dh
        object.total_cents / 100
      end

      def sendit
        object
      end

      def items
        object.order_items
      end
    end
  end
end
