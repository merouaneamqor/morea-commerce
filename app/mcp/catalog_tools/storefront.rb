# frozen_string_literal: true

module CatalogTools
  module Storefront
    SETTINGS = <<~GQL.squish
      name slug origin currency phone whatsapp email paymentMethod
      shippingDh freeShippingThresholdDh lowStockThreshold
      senditConfigured senditPickupDistrictId senditAllowOpen senditAllowTry discordConfigured
      metaPixelId tiktokPixelId featuredProductSlug featuredCollectionSlug
      legalEntityName cndpAuthorization privacyRightsContact
      translations { locale tagline about codLabel codNote campaignTitle campaignSeason campaignCta announcement }
    GQL

    class GetStoreSettings < MCP::Tool
      description "Read checkout, cash-on-delivery copy, fallback shipping, Sendit status, pixels, and the public store URL. Secrets are not returned. Cash on delivery is the only payment gateway. The public host is origin; custom domains are not available."

      def self.call(server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: "query { storeSettings { #{SETTINGS} } }"
        )
      end
    end

    class UpdateCheckout < MCP::Tool
      description "Update cash on delivery copy, contact details, fallback shipping price, free-shipping threshold, low-stock threshold, featured product or collection, and the legal name used on the privacy page. Omitted fields stay unchanged. clearFreeShipping removes the threshold. Payment stays cash on delivery."
      input_schema(
        properties: {
          phone: { type: "string" },
          whatsapp: { type: "string" },
          email: { type: "string" },
          currency: { type: "string" },
          shippingDh: { type: "integer" },
          freeShippingThresholdDh: { type: "integer" },
          clearFreeShipping: { type: "boolean" },
          lowStockThreshold: { type: "integer" },
          legalEntityName: { type: "string" },
          cndpAuthorization: { type: "string" },
          privacyRightsContact: { type: "string" },
          featuredProductSlug: { type: "string" },
          clearFeaturedProduct: { type: "boolean" },
          featuredCollectionSlug: { type: "string" },
          clearFeaturedCollection: { type: "boolean" },
          translations: { type: "array", items: { type: "object" }, description: "locale plus tagline, about, codLabel, codNote, campaignTitle, campaignSeason, campaignCta, announcement" }
        }
      )

      def self.call(server_context:, **attrs)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: <<~GQL,
            mutation(
              $phone: String, $whatsapp: String, $email: String, $currency: String,
              $shippingDh: Int, $freeShippingThresholdDh: Int, $clearFreeShipping: Boolean,
              $lowStockThreshold: Int, $legalEntityName: String, $cndpAuthorization: String,
              $privacyRightsContact: String, $featuredProductSlug: String, $clearFeaturedProduct: Boolean,
              $featuredCollectionSlug: String, $clearFeaturedCollection: Boolean, $translations: [StorefrontCopyInput!]
            ) {
              updateCheckout(
                phone: $phone, whatsapp: $whatsapp, email: $email, currency: $currency,
                shippingDh: $shippingDh, freeShippingThresholdDh: $freeShippingThresholdDh,
                clearFreeShipping: $clearFreeShipping, lowStockThreshold: $lowStockThreshold,
                legalEntityName: $legalEntityName, cndpAuthorization: $cndpAuthorization,
                privacyRightsContact: $privacyRightsContact, featuredProductSlug: $featuredProductSlug,
                clearFeaturedProduct: $clearFeaturedProduct, featuredCollectionSlug: $featuredCollectionSlug,
                clearFeaturedCollection: $clearFeaturedCollection, translations: $translations
              ) { settings { #{SETTINGS} } errors }
            }
          GQL
          variables: attrs.compact
        )
      end
    end

    class UpdateMarketing < MCP::Tool
      description "Set the Meta and TikTok pixel ids. These are the store's marketing tags. There is no email or SMS campaign sender. clearMetaPixel or clearTiktokPixel removes an id."
      input_schema(
        properties: {
          metaPixelId: { type: "string" },
          clearMetaPixel: { type: "boolean" },
          tiktokPixelId: { type: "string" },
          clearTiktokPixel: { type: "boolean" }
        }
      )

      def self.call(server_context:, **attrs)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: <<~GQL,
            mutation($metaPixelId: String, $clearMetaPixel: Boolean, $tiktokPixelId: String, $clearTiktokPixel: Boolean) {
              updateMarketing(metaPixelId: $metaPixelId, clearMetaPixel: $clearMetaPixel, tiktokPixelId: $tiktokPixelId, clearTiktokPixel: $clearTiktokPixel) {
                settings { metaPixelId tiktokPixelId }
                errors
              }
            }
          GQL
          variables: attrs.compact
        )
      end
    end

    class UpdateShipping < MCP::Tool
      description "Configure Sendit, the shipping provider: API keys, webhook secret, pickup district id, allow-open, allow-try, and the Discord order webhook. Blank secrets stay unchanged. clearSendit or clearDiscord removes them. Keys are never returned."
      input_schema(
        properties: {
          senditPublicKey: { type: "string" },
          senditSecretKey: { type: "string" },
          senditWebhookSecret: { type: "string" },
          clearSendit: { type: "boolean" },
          pickupDistrictId: { type: "integer" },
          allowOpen: { type: "boolean" },
          allowTry: { type: "boolean" },
          discordOrdersWebhookUrl: { type: "string" },
          clearDiscord: { type: "boolean" }
        }
      )

      def self.call(server_context:, **attrs)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: <<~GQL,
            mutation(
              $senditPublicKey: String, $senditSecretKey: String, $senditWebhookSecret: String,
              $clearSendit: Boolean, $pickupDistrictId: Int, $allowOpen: Boolean, $allowTry: Boolean,
              $discordOrdersWebhookUrl: String, $clearDiscord: Boolean
            ) {
              updateShipping(
                senditPublicKey: $senditPublicKey, senditSecretKey: $senditSecretKey,
                senditWebhookSecret: $senditWebhookSecret, clearSendit: $clearSendit,
                pickupDistrictId: $pickupDistrictId, allowOpen: $allowOpen, allowTry: $allowTry,
                discordOrdersWebhookUrl: $discordOrdersWebhookUrl, clearDiscord: $clearDiscord
              ) { settings { senditConfigured senditPickupDistrictId senditAllowOpen senditAllowTry discordConfigured } errors }
            }
          GQL
          variables: attrs.compact
        )
      end
    end

    class SyncShipping < MCP::Tool
      description "Queue a Sendit sync for open parcels: push orders that have no parcel yet and refresh the rest. Requires confirm: true. Fails when Sendit is not configured."
      input_schema(properties: { confirm: { type: "boolean" } }, required: [ "confirm" ])

      def self.call(confirm:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: "mutation($confirm: Boolean!) { syncShipping(confirm: $confirm) { queued errors } }",
          variables: { confirm: confirm }
        )
      end
    end

    class InstallTheme < MCP::Tool
      description "Install the default home page, starter pages, and menus only where that part is still empty. Requires confirm: true. Does not replace sections, pages, or menus that already exist."
      input_schema(properties: { confirm: { type: "boolean" } }, required: [ "confirm" ])

      def self.call(confirm:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: "mutation($confirm: Boolean!) { installTheme(confirm: $confirm) { installed errors } }",
          variables: { confirm: confirm }
        )
      end
    end

    class ListDiscounts < MCP::Tool
      description "List coupon codes. value is a percent, or whole currency units when discountType is fixed."

      def self.call(server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: "query { discounts { code discountType value active startsAt endsAt label } }"
        )
      end
    end

    class UpsertDiscount < MCP::Tool
      description "Create or update a coupon by code. discountType is percent or fixed. value is 1-100 for percent, or whole currency units for fixed. clearEnds removes the end date."
      input_schema(
        properties: {
          code: { type: "string" },
          discountType: { type: "string", enum: %w[percent fixed] },
          value: { type: "integer" },
          active: { type: "boolean" },
          startsAt: { type: "string", description: "ISO8601" },
          endsAt: { type: "string", description: "ISO8601" },
          clearEnds: { type: "boolean" }
        },
        required: [ "code" ]
      )

      def self.call(code:, server_context:, **attrs)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: <<~GQL,
            mutation($code: String!, $discountType: String, $value: Int, $active: Boolean, $startsAt: ISO8601DateTime, $endsAt: ISO8601DateTime, $clearEnds: Boolean) {
              upsertDiscount(code: $code, discountType: $discountType, value: $value, active: $active, startsAt: $startsAt, endsAt: $endsAt, clearEnds: $clearEnds) {
                discount { code discountType value active startsAt endsAt label }
                errors
              }
            }
          GQL
          variables: { code: code }.merge(attrs.compact)
        )
      end
    end

    class DeleteDiscount < MCP::Tool
      description "Delete a coupon by code. Requires confirm: true."
      input_schema(
        properties: { code: { type: "string" }, confirm: { type: "boolean" } },
        required: %w[code confirm]
      )

      def self.call(code:, confirm:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: "mutation($code: String!, $confirm: Boolean!) { deleteDiscount(code: $code, confirm: $confirm) { deleted errors } }",
          variables: { code: code, confirm: confirm }
        )
      end
    end

    class ListActiveCarts < MCP::Tool
      description "List carts that still have items and were updated within withinHours (default 1). These are shoppers still building a bag. Carts are anonymous: there is no email or phone."
      input_schema(
        properties: {
          withinHours: { type: "integer", description: "1-720, default 1" },
          limit: { type: "integer", description: "1-100, default 50" }
        }
      )

      def self.call(server_context:, **attrs)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: <<~GQL,
            query($withinHours: Int, $limit: Int) {
              activeCarts(withinHours: $withinHours, limit: $limit) {
                updatedAt itemCount subtotalDh
                items { productSlug productName variantName quantity unitPriceDh totalDh }
              }
            }
          GQL
          variables: attrs.compact
        )
      end
    end

    class ListAbandonedCarts < MCP::Tool
      description "List carts that still have items and have not been updated for olderThanHours (default 1, 0 means all). Carts are anonymous: there is no email or phone to send a recovery message."
      input_schema(
        properties: {
          olderThanHours: { type: "integer" },
          limit: { type: "integer", description: "1-100, default 50" }
        }
      )

      def self.call(server_context:, **attrs)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: <<~GQL,
            query($olderThanHours: Int, $limit: Int) {
              abandonedCarts(olderThanHours: $olderThanHours, limit: $limit) {
                updatedAt itemCount subtotalDh
                items { productSlug productName variantName quantity unitPriceDh totalDh }
              }
            }
          GQL
          variables: attrs.compact
        )
      end
    end

    class ListCustomers < MCP::Tool
      description "List customers. Includes name, phone, email, and city. Order tools still omit phone and email."
      input_schema(
        properties: {
          query: { type: "string" },
          limit: { type: "integer", description: "1-100, default 50" }
        }
      )

      def self.call(server_context:, **attrs)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: <<~GQL,
            query($query: String, $limit: Int) {
              customers(query: $query, limit: $limit) { name phone email city ordersCount createdAt }
            }
          GQL
          variables: attrs.compact
        )
      end
    end

    class GetCustomer < MCP::Tool
      description "Get one customer by phone, including saved addresses."
      input_schema(properties: { phone: { type: "string" } }, required: [ "phone" ])

      def self.call(phone:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: <<~GQL,
            query($phone: String!) {
              customer(phone: $phone) {
                name phone email city ordersCount createdAt
                addresses { city line1 line2 primary }
              }
            }
          GQL
          variables: { phone: phone }
        )
      end
    end

    class UpsertCustomer < MCP::Tool
      description "Create or update a customer by phone. A new customer needs a name. newPhone renames the phone."
      input_schema(
        properties: {
          phone: { type: "string" },
          name: { type: "string" },
          email: { type: "string" },
          city: { type: "string" },
          newPhone: { type: "string" }
        },
        required: [ "phone" ]
      )

      def self.call(phone:, server_context:, **attrs)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: <<~GQL,
            mutation($phone: String!, $name: String, $email: String, $city: String, $newPhone: String) {
              upsertCustomer(phone: $phone, name: $name, email: $email, city: $city, newPhone: $newPhone) {
                customer { name phone email city ordersCount }
                errors
              }
            }
          GQL
          variables: { phone: phone }.merge(attrs.compact)
        )
      end
    end

    class ExportCsv < MCP::Tool
      description "Export products, orders, customers, or discounts as CSV text. Orders omit phone, street address, and email. At most 500 rows; truncated is true when more exist."
      input_schema(
        properties: { kind: { type: "string", enum: %w[products orders customers discounts] } },
        required: [ "kind" ]
      )

      def self.call(kind:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: "query($kind: String!) { exportCsv(kind: $kind) { csv rows truncated } }",
          variables: { kind: kind }
        )
      end
    end

    class ImportCsv < MCP::Tool
      description "Import a CSV. kind is products, customers, or discounts. Requires confirm: true. Products use slug,status,priceDh,stock,sku,nameFr,nameEn,nameAr. Customers use name,phone,email,city. Discounts use code,type,value,active,startsAt,endsAt. At most 200 rows. Existing records are updated."
      input_schema(
        properties: {
          kind: { type: "string", enum: %w[products customers discounts] },
          csv: { type: "string" },
          confirm: { type: "boolean" }
        },
        required: %w[kind csv confirm]
      )

      def self.call(kind:, csv:, confirm:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: <<~GQL,
            mutation($kind: String!, $csv: String!, $confirm: Boolean!) {
              importCsv(kind: $kind, csv: $csv, confirm: $confirm) { result { imported errors } errors }
            }
          GQL
          variables: { kind: kind, csv: csv, confirm: confirm }
        )
      end
    end

    class ListHomeSections < MCP::Tool
      description "List home-page builder blocks in storefront order. Prefer get_home_layout for the full builder view. kind is hero, ticker, featured_collection, collection_list, image_with_text, or rich_text."

      def self.call(server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: <<~GQL
            query { homeSections { id kind label position visible imageUrl imageSrc link collectionSlug limit imagePosition translations { locale heading subheading body buttonLabel } } }
          GQL
        )
      end
    end

    class UpsertHomeSection < MCP::Tool
      description "Add or update a home-page block. A new block needs kind. link is home, collections, cart, track, collection:slug, product:slug, page:slug, or a URL. imagePosition is left or right."
      input_schema(
        properties: {
          id: { type: "string" },
          kind: { type: "string", enum: %w[hero ticker featured_collection collection_list image_with_text rich_text] },
          visible: { type: "boolean" },
          position: { type: "integer" },
          imageUrl: { type: "string" },
          link: { type: "string" },
          collectionSlug: { type: "string" },
          limit: { type: "integer" },
          imagePosition: { type: "string", enum: %w[left right] },
          translations: { type: "array", items: { type: "object" } }
        }
      )

      def self.call(server_context:, **attrs)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: <<~GQL,
            mutation(
              $id: ID, $kind: String, $visible: Boolean, $position: Int, $imageUrl: String, $link: String,
              $collectionSlug: String, $limit: Int, $imagePosition: String, $translations: [StorefrontSectionCopyInput!]
            ) {
              upsertHomeSection(
                id: $id, kind: $kind, visible: $visible, position: $position, imageUrl: $imageUrl, link: $link,
                collectionSlug: $collectionSlug, limit: $limit, imagePosition: $imagePosition, translations: $translations
              ) { section { id kind position visible } errors }
            }
          GQL
          variables: attrs.compact
        )
      end
    end

    class DeleteHomeSection < MCP::Tool
      description "Remove a home-page block by id. Requires confirm: true."
      input_schema(
        properties: { id: { type: "string" }, confirm: { type: "boolean" } },
        required: %w[id confirm]
      )

      def self.call(id:, confirm:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: "mutation($id: ID!, $confirm: Boolean!) { deleteHomeSection(id: $id, confirm: $confirm) { deleted errors } }",
          variables: { id: id, confirm: confirm }
        )
      end
    end

    class ListPages < MCP::Tool
      description "List content and landing pages. template is content or landing. Prefer list_landing_pages / get_landing_page for landing builders."

      def self.call(server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: "query { pages { slug published template translations { locale title body seoTitle seoDescription } } }"
        )
      end
    end

    class UpsertPage < MCP::Tool
      description "Create or update a page. Pass slug to update. A new page needs a fr title. newSlug renames. template is content or landing. Prefer upsert_landing_page for campaign landings."
      input_schema(
        properties: {
          slug: { type: "string" },
          newSlug: { type: "string" },
          published: { type: "boolean" },
          template: { type: "string", enum: %w[content landing] },
          translations: { type: "array", items: { type: "object" }, description: "locale, title, body, seoTitle, seoDescription" }
        }
      )

      def self.call(server_context:, **attrs)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: <<~GQL,
            mutation($slug: String, $newSlug: String, $published: Boolean, $template: String, $translations: [StorefrontPageCopyInput!]) {
              upsertPage(slug: $slug, newSlug: $newSlug, published: $published, template: $template, translations: $translations) {
                page { slug published template }
                errors
              }
            }
          GQL
          variables: attrs.compact
        )
      end
    end

    class DeletePage < MCP::Tool
      description "Delete a content page by slug. Requires confirm: true. The privacy page cannot be deleted."
      input_schema(
        properties: { slug: { type: "string" }, confirm: { type: "boolean" } },
        required: %w[slug confirm]
      )

      def self.call(slug:, confirm:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: "mutation($slug: String!, $confirm: Boolean!) { deletePage(slug: $slug, confirm: $confirm) { deleted errors } }",
          variables: { slug: slug, confirm: confirm }
        )
      end
    end

    class ListMenuItems < MCP::Tool
      description "List header and footer navigation links."

      def self.call(server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: "query { menuItems { id menu link position translations { locale label } } }"
        )
      end
    end

    class UpsertMenuItem < MCP::Tool
      description "Add or update a header or footer link. A new item needs menu, link, and a fr label. link is home, collections, cart, track, collection:slug, product:slug, page:slug, or a URL."
      input_schema(
        properties: {
          id: { type: "string" },
          menu: { type: "string", enum: %w[header footer] },
          link: { type: "string" },
          position: { type: "integer" },
          translations: { type: "array", items: { type: "object" } }
        }
      )

      def self.call(server_context:, **attrs)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: <<~GQL,
            mutation($id: ID, $menu: String, $link: String, $position: Int, $translations: [StorefrontMenuCopyInput!]) {
              upsertMenuItem(id: $id, menu: $menu, link: $link, position: $position, translations: $translations) {
                menuItem { id menu link position }
                errors
              }
            }
          GQL
          variables: attrs.compact
        )
      end
    end

    class DeleteMenuItem < MCP::Tool
      description "Remove a navigation link by id. Requires confirm: true."
      input_schema(
        properties: { id: { type: "string" }, confirm: { type: "boolean" } },
        required: %w[id confirm]
      )

      def self.call(id:, confirm:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: "mutation($id: ID!, $confirm: Boolean!) { deleteMenuItem(id: $id, confirm: $confirm) { deleted errors } }",
          variables: { id: id, confirm: confirm }
        )
      end
    end
  end
end
