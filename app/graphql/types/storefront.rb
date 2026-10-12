# frozen_string_literal: true

module Types
  module Storefront
    class CopyType < BaseObject
      field :locale, String, null: false
      field :tagline, String, null: true
      field :about, String, null: true
      field :cod_label, String, null: true
      field :cod_note, String, null: true
      field :campaign_title, String, null: true
      field :campaign_season, String, null: true
      field :campaign_cta, String, null: true
      field :announcement, String, null: true
    end

    class SettingsType < BaseObject
      field :name, String, null: false
      field :slug, String, null: false
      field :origin, String, null: false
      field :currency, String, null: false
      field :phone, String, null: true
      field :whatsapp, String, null: true
      field :email, String, null: true
      field :payment_method, String, null: false
      field :shipping_dh, Integer, null: false
      field :free_shipping_threshold_dh, Integer, null: true
      field :low_stock_threshold, Integer, null: false
      field :sendit_configured, Boolean, null: false
      field :sendit_pickup_district_id, Integer, null: true
      field :sendit_allow_open, Boolean, null: false
      field :sendit_allow_try, Boolean, null: false
      field :discord_configured, Boolean, null: false
      field :meta_pixel_id, String, null: true
      field :tiktok_pixel_id, String, null: true
      field :featured_product_slug, String, null: true
      field :featured_collection_slug, String, null: true
      field :legal_entity_name, String, null: true
      field :cndp_authorization, String, null: true
      field :privacy_rights_contact, String, null: true
      field :translations, [ CopyType ], null: false

      def payment_method
        "cod"
      end

      def sendit_configured
        object.sendit_configured?
      end

      def discord_configured
        object.discord_orders_webhook_url.present?
      end

      def featured_product_slug
        object.featured_product&.slug
      end

      def featured_collection_slug
        object.featured_collection&.slug
      end

      def translations
        object.translations.sort_by(&:locale)
      end
    end

    class DiscountType < BaseObject
      field :code, String, null: false
      field :discount_type, String, null: false
      field :value, Integer, null: false
      field :active, Boolean, null: false
      field :starts_at, GraphQL::Types::ISO8601DateTime, null: true
      field :ends_at, GraphQL::Types::ISO8601DateTime, null: true
      field :label, String, null: false
    end

    class AddressType < BaseObject
      field :city, String, null: false
      field :line1, String, null: false
      field :line2, String, null: true
      field :primary, Boolean, null: false

      def primary
        object.default
      end
    end

    class CustomerType < BaseObject
      field :name, String, null: false
      field :phone, String, null: false
      field :email, String, null: true
      field :city, String, null: true
      field :orders_count, Integer, null: false
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :addresses, [ AddressType ], null: false

      def addresses
        object.addresses.order(default: :desc, created_at: :desc)
      end
    end

    class CartLineType < BaseObject
      field :product_slug, String, null: true
      field :product_name, String, null: false
      field :variant_name, String, null: true
      field :quantity, Integer, null: false
      field :unit_price_dh, Integer, null: false
      field :total_dh, Integer, null: false

      def product_slug
        object.product&.slug
      end

      def product_name
        object.product&.name.to_s
      end

      def variant_name
        object.product_variant&.display_name
      end

      def unit_price_dh
        object.unit_price_cents / 100
      end

      def total_dh
        object.line_total_cents / 100
      end
    end

    class AbandonedCartType < BaseObject
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :item_count, Integer, null: false
      field :subtotal_dh, Integer, null: false
      field :items, [ CartLineType ], null: false

      def subtotal_dh
        object.subtotal_cents / 100
      end

      def items
        object.cart_items
      end
    end

    class SectionCopyType < BaseObject
      field :locale, String, null: false
      field :heading, String, null: true
      field :subheading, String, null: true
      field :body, String, null: true
      field :button_label, String, null: true
    end

    class SectionType < BaseObject
      field :id, ID, null: false
      field :kind, String, null: false
      field :position, Integer, null: false
      field :visible, Boolean, null: false
      field :image_url, String, null: true
      field :link, String, null: true
      field :collection_slug, String, null: true
      field :limit, Integer, null: true
      field :image_position, String, null: true
      field :translations, [ SectionCopyType ], null: false

      def image_url
        object.image_url.presence
      end

      def collection_slug
        object.store.collections.find_by(id: object.collection_id)&.slug if object.collection_id.present?
      end

      def limit
        object.limit.presence&.to_i
      end

      def translations
        object.translations.sort_by(&:locale)
      end
    end

    class PageCopyType < BaseObject
      field :locale, String, null: false
      field :title, String, null: true
      field :body, String, null: true
      field :seo_title, String, null: true
      field :seo_description, String, null: true
    end

    class PageType < BaseObject
      field :slug, String, null: false
      field :published, Boolean, null: false
      field :translations, [ PageCopyType ], null: false

      def translations
        object.translations.sort_by(&:locale)
      end
    end

    class MenuCopyType < BaseObject
      field :locale, String, null: false
      field :label, String, null: true
    end

    class MenuItemType < BaseObject
      field :id, ID, null: false
      field :menu, String, null: false
      field :link, String, null: false
      field :position, Integer, null: false
      field :translations, [ MenuCopyType ], null: false

      def translations
        object.translations.sort_by(&:locale)
      end
    end

    class CsvExportType < BaseObject
      field :csv, String, null: false
      field :rows, Integer, null: false
      field :truncated, Boolean, null: false
    end

    class CsvImportType < BaseObject
      field :imported, Integer, null: false
      field :errors, [ String ], null: false
    end

    class CopyInput < BaseInput
      graphql_name "StorefrontCopyInput"
      argument :locale, String, required: true
      argument :tagline, String, required: false
      argument :about, String, required: false
      argument :cod_label, String, required: false
      argument :cod_note, String, required: false
      argument :campaign_title, String, required: false
      argument :campaign_season, String, required: false
      argument :campaign_cta, String, required: false
      argument :announcement, String, required: false
    end

    class SectionCopyInput < BaseInput
      graphql_name "StorefrontSectionCopyInput"
      argument :locale, String, required: true
      argument :heading, String, required: false
      argument :subheading, String, required: false
      argument :body, String, required: false
      argument :button_label, String, required: false
    end

    class PageCopyInput < BaseInput
      graphql_name "StorefrontPageCopyInput"
      argument :locale, String, required: true
      argument :title, String, required: false
      argument :body, String, required: false
      argument :seo_title, String, required: false
      argument :seo_description, String, required: false
    end

    class MenuCopyInput < BaseInput
      graphql_name "StorefrontMenuCopyInput"
      argument :locale, String, required: true
      argument :label, String, required: false
    end
  end
end
