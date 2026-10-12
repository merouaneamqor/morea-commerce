# frozen_string_literal: true

module Mutations
  module Storefront
    class UpdateCheckout < BaseMutation
      argument :phone, String, required: false
      argument :whatsapp, String, required: false
      argument :email, String, required: false
      argument :currency, String, required: false
      argument :shipping_dh, Integer, required: false
      argument :free_shipping_threshold_dh, Integer, required: false
      argument :clear_free_shipping, Boolean, required: false
      argument :low_stock_threshold, Integer, required: false
      argument :legal_entity_name, String, required: false
      argument :cndp_authorization, String, required: false
      argument :privacy_rights_contact, String, required: false
      argument :featured_product_slug, String, required: false
      argument :clear_featured_product, Boolean, required: false
      argument :featured_collection_slug, String, required: false
      argument :clear_featured_collection, Boolean, required: false
      argument :translations, [ Types::Storefront::CopyInput ], required: false

      field :settings, Types::Storefront::SettingsType, null: true
      field :errors, [ String ], null: false

      def resolve(**attrs)
        { settings: Catalog::StoreOps.update_checkout!(store, attrs), errors: [] }
      rescue Catalog::StoreOps::Error => e
        { settings: nil, errors: [ e.message ] }
      end
    end

    class UpdateMarketing < BaseMutation
      argument :meta_pixel_id, String, required: false
      argument :clear_meta_pixel, Boolean, required: false
      argument :tiktok_pixel_id, String, required: false
      argument :clear_tiktok_pixel, Boolean, required: false

      field :settings, Types::Storefront::SettingsType, null: true
      field :errors, [ String ], null: false

      def resolve(**attrs)
        { settings: Catalog::StoreOps.update_marketing!(store, attrs), errors: [] }
      rescue Catalog::StoreOps::Error => e
        { settings: nil, errors: [ e.message ] }
      end
    end

    class UpdateShipping < BaseMutation
      argument :sendit_public_key, String, required: false
      argument :sendit_secret_key, String, required: false
      argument :sendit_webhook_secret, String, required: false
      argument :clear_sendit, Boolean, required: false
      argument :pickup_district_id, Integer, required: false
      argument :allow_open, Boolean, required: false
      argument :allow_try, Boolean, required: false
      argument :discord_orders_webhook_url, String, required: false
      argument :clear_discord, Boolean, required: false

      field :settings, Types::Storefront::SettingsType, null: true
      field :errors, [ String ], null: false

      def resolve(**attrs)
        { settings: Catalog::StoreOps.update_shipping!(store, attrs), errors: [] }
      rescue Catalog::StoreOps::Error => e
        { settings: nil, errors: [ e.message ] }
      end
    end

    class SyncShipping < BaseMutation
      argument :confirm, Boolean, required: true

      field :queued, Integer, null: true
      field :errors, [ String ], null: false

      def resolve(confirm:)
        { queued: Catalog::StoreOps.sync_shipping!(store, confirm: confirm), errors: [] }
      rescue Catalog::StoreOps::Error => e
        { queued: nil, errors: [ e.message ] }
      end
    end

    class InstallTheme < BaseMutation
      argument :confirm, Boolean, required: true

      field :installed, Boolean, null: false
      field :errors, [ String ], null: false

      def resolve(confirm:)
        Catalog::StoreOps.install_theme!(store, confirm: confirm)
        { installed: true, errors: [] }
      rescue Catalog::StoreOps::Error => e
        { installed: false, errors: [ e.message ] }
      end
    end

    class UpsertDiscount < BaseMutation
      argument :code, String, required: true
      argument :discount_type, String, required: false
      argument :value, Integer, required: false
      argument :active, Boolean, required: false
      argument :starts_at, GraphQL::Types::ISO8601DateTime, required: false
      argument :ends_at, GraphQL::Types::ISO8601DateTime, required: false
      argument :clear_ends, Boolean, required: false

      field :discount, Types::Storefront::DiscountType, null: true
      field :errors, [ String ], null: false

      def resolve(**attrs)
        { discount: Catalog::StoreOps.upsert_discount!(store, attrs), errors: [] }
      rescue Catalog::StoreOps::Error => e
        { discount: nil, errors: [ e.message ] }
      end
    end

    class DeleteDiscount < BaseMutation
      argument :code, String, required: true
      argument :confirm, Boolean, required: true

      field :deleted, Boolean, null: false
      field :errors, [ String ], null: false

      def resolve(code:, confirm:)
        Catalog::StoreOps.delete_discount!(store, code: code, confirm: confirm)
        { deleted: true, errors: [] }
      rescue Catalog::StoreOps::Error => e
        { deleted: false, errors: [ e.message ] }
      end
    end

    class UpsertCustomer < BaseMutation
      argument :phone, String, required: true
      argument :name, String, required: false
      argument :email, String, required: false
      argument :city, String, required: false
      argument :new_phone, String, required: false

      field :customer, Types::Storefront::CustomerType, null: true
      field :errors, [ String ], null: false

      def resolve(**attrs)
        { customer: Catalog::StoreOps.upsert_customer!(store, attrs), errors: [] }
      rescue Catalog::StoreOps::Error => e
        { customer: nil, errors: [ e.message ] }
      end
    end

    class ImportCsv < BaseMutation
      argument :kind, String, required: true
      argument :csv, String, required: true
      argument :confirm, Boolean, required: true

      field :result, Types::Storefront::CsvImportType, null: true
      field :errors, [ String ], null: false

      def resolve(kind:, csv:, confirm:)
        result = Catalog::StoreOps.import_csv!(store, kind: kind, csv: csv, confirm: confirm)
        { result: result, errors: result.errors }
      rescue Catalog::StoreOps::Error => e
        { result: nil, errors: [ e.message ] }
      end
    end

    class UpsertHomeSection < BaseMutation
      argument :id, ID, required: false
      argument :kind, String, required: false
      argument :visible, Boolean, required: false
      argument :position, Integer, required: false
      argument :image_url, String, required: false
      argument :link, String, required: false
      argument :collection_slug, String, required: false
      argument :limit, Integer, required: false
      argument :image_position, String, required: false
      argument :translations, [ Types::Storefront::SectionCopyInput ], required: false

      field :section, Types::Storefront::SectionType, null: true
      field :errors, [ String ], null: false

      def resolve(**attrs)
        { section: Catalog::StoreOps.upsert_section!(store, attrs), errors: [] }
      rescue Catalog::StoreOps::Error => e
        { section: nil, errors: [ e.message ] }
      end
    end

    class DeleteHomeSection < BaseMutation
      argument :id, ID, required: true
      argument :confirm, Boolean, required: true

      field :deleted, Boolean, null: false
      field :errors, [ String ], null: false

      def resolve(id:, confirm:)
        Catalog::StoreOps.delete_section!(store, id: id, confirm: confirm)
        { deleted: true, errors: [] }
      rescue Catalog::StoreOps::Error => e
        { deleted: false, errors: [ e.message ] }
      end
    end

    class UpsertPage < BaseMutation
      argument :slug, String, required: false
      argument :new_slug, String, required: false
      argument :published, Boolean, required: false
      argument :translations, [ Types::Storefront::PageCopyInput ], required: false

      field :page, Types::Storefront::PageType, null: true
      field :errors, [ String ], null: false

      def resolve(**attrs)
        { page: Catalog::StoreOps.upsert_page!(store, attrs), errors: [] }
      rescue Catalog::StoreOps::Error => e
        { page: nil, errors: [ e.message ] }
      end
    end

    class DeletePage < BaseMutation
      argument :slug, String, required: true
      argument :confirm, Boolean, required: true

      field :deleted, Boolean, null: false
      field :errors, [ String ], null: false

      def resolve(slug:, confirm:)
        Catalog::StoreOps.delete_page!(store, slug: slug, confirm: confirm)
        { deleted: true, errors: [] }
      rescue Catalog::StoreOps::Error => e
        { deleted: false, errors: [ e.message ] }
      end
    end

    class UpsertMenuItem < BaseMutation
      argument :id, ID, required: false
      argument :menu, String, required: false
      argument :link, String, required: false
      argument :position, Integer, required: false
      argument :translations, [ Types::Storefront::MenuCopyInput ], required: false

      field :menu_item, Types::Storefront::MenuItemType, null: true
      field :errors, [ String ], null: false

      def resolve(**attrs)
        { menu_item: Catalog::StoreOps.upsert_menu_item!(store, attrs), errors: [] }
      rescue Catalog::StoreOps::Error => e
        { menu_item: nil, errors: [ e.message ] }
      end
    end

    class DeleteMenuItem < BaseMutation
      argument :id, ID, required: true
      argument :confirm, Boolean, required: true

      field :deleted, Boolean, null: false
      field :errors, [ String ], null: false

      def resolve(id:, confirm:)
        Catalog::StoreOps.delete_menu_item!(store, id: id, confirm: confirm)
        { deleted: true, errors: [] }
      rescue Catalog::StoreOps::Error => e
        { deleted: false, errors: [ e.message ] }
      end
    end
  end
end
