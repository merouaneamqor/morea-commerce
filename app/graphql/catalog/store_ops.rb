# frozen_string_literal: true

require "csv"

module Catalog
  module StoreOps
    class Error < StandardError; end

    Export = Data.define(:csv, :rows, :truncated)
    Import = Data.define(:imported, :errors)
    MAX_IMPORT = 200
    MAX_EXPORT = 500
    EXPORT_KINDS = %w[products orders customers discounts].freeze
    IMPORT_KINDS = %w[products customers discounts].freeze

    module_function

    def update_checkout!(store, attrs)
      attrs = attrs.to_h.symbolize_keys
      assign_present(store, attrs, :phone, :whatsapp, :email, :currency, :legal_entity_name, :cndp_authorization, :privacy_rights_contact)
      store.shipping_dh = attrs[:shipping_dh] unless attrs[:shipping_dh].nil?
      store.low_stock_threshold = attrs[:low_stock_threshold] unless attrs[:low_stock_threshold].nil?
      if attrs[:clear_free_shipping]
        store.free_shipping_threshold_cents = nil
      elsif !attrs[:free_shipping_threshold_dh].nil?
        store.free_shipping_threshold_dh = attrs[:free_shipping_threshold_dh]
      end
      assign_featured!(store, :featured_product, attrs[:featured_product_slug], attrs[:clear_featured_product], store.products)
      assign_featured!(store, :featured_collection, attrs[:featured_collection_slug], attrs[:clear_featured_collection], store.collections)
      Translations.assign!(store, attrs[:translations]) if attrs[:translations]
      save!(store)
    end

    def update_marketing!(store, attrs)
      attrs = attrs.to_h.symbolize_keys
      if attrs[:clear_meta_pixel]
        store.meta_pixel_id = nil
      elsif attrs[:meta_pixel_id].present?
        store.meta_pixel_id = attrs[:meta_pixel_id]
      end
      if attrs[:clear_tiktok_pixel]
        store.tiktok_pixel_id = nil
      elsif attrs[:tiktok_pixel_id].present?
        store.tiktok_pixel_id = attrs[:tiktok_pixel_id]
      end
      save!(store)
    end

    def update_shipping!(store, attrs)
      attrs = attrs.to_h.symbolize_keys
      if attrs[:clear_sendit]
        store.assign_attributes(sendit_public_key: nil, sendit_secret_key: nil, sendit_webhook_secret: nil)
      else
        store.sendit_public_key = attrs[:sendit_public_key] if attrs[:sendit_public_key].present?
        store.sendit_secret_key = attrs[:sendit_secret_key] if attrs[:sendit_secret_key].present?
        store.sendit_webhook_secret = attrs[:sendit_webhook_secret] if attrs[:sendit_webhook_secret].present?
      end
      if attrs[:clear_discord]
        store.discord_orders_webhook_url = nil
      elsif attrs[:discord_orders_webhook_url].present?
        url = attrs[:discord_orders_webhook_url].to_s.strip
        raise Error, "Discord webhook must be an https URL." unless url.match?(/\Ahttps:\/\//)

        store.discord_orders_webhook_url = url
      end
      store.sendit_pickup_district_id = attrs[:pickup_district_id] unless attrs[:pickup_district_id].nil?
      store.sendit_allow_open = attrs[:allow_open] unless attrs[:allow_open].nil?
      store.sendit_allow_try = attrs[:allow_try] unless attrs[:allow_try].nil?
      save!(store)
    end

    def sync_shipping!(store, confirm:)
      raise Error, "Set confirm: true to sync shipping." unless confirm
      raise Error, "Sendit is not configured." unless store.sendit_configured?

      Sendit::Sync.enqueue_all(store.orders)
    end

    def install_theme!(store, confirm:)
      raise Error, "Set confirm: true to install the default theme." unless confirm

      store.install_online_store_defaults!
      store
    end

    def upsert_discount!(store, attrs)
      attrs = attrs.to_h.symbolize_keys
      code = attrs[:code].to_s.strip.upcase
      raise Error, "Code is required." if code.blank?

      discount = store.discounts.find_or_initialize_by(code: code)
      discount.discount_type = attrs[:discount_type] if attrs[:discount_type].present?
      discount.value = attrs[:value] unless attrs[:value].nil?
      discount.active = attrs[:active] unless attrs[:active].nil?
      discount.starts_at = attrs[:starts_at] unless attrs[:starts_at].nil?
      discount.ends_at = nil if attrs[:clear_ends]
      discount.ends_at = attrs[:ends_at] unless attrs[:ends_at].nil?
      raise Error, "discountType and value are required for a new code." if discount.new_record? && (discount.discount_type.blank? || discount.value.nil?)

      save!(discount)
    end

    def delete_discount!(store, code:, confirm:)
      raise Error, "Set confirm: true to delete." unless confirm

      discount = store.discounts.find_by(code: code.to_s.strip.upcase)
      raise Error, "Discount not found: #{code}" unless discount

      discount.destroy!
      true
    end

    def upsert_customer!(store, attrs)
      attrs = attrs.to_h.symbolize_keys
      phone = normalize_phone(attrs[:phone])
      raise Error, "Phone is required." if phone.blank?

      customer = store.customers.find_by(phone: phone) || store.customers.new(phone: phone)
      customer.name = attrs[:name] if attrs[:name].present?
      raise Error, "Name is required for a new customer." if customer.new_record? && customer.name.blank?

      customer.email = attrs[:email] if attrs.key?(:email) && !attrs[:email].nil?
      customer.city = attrs[:city] if attrs.key?(:city) && !attrs[:city].nil?
      if attrs[:new_phone].present?
        customer.phone = normalize_phone(attrs[:new_phone])
      end
      save!(customer)
    end

    def abandoned_carts(store, older_than_hours:, limit:)
      hours = older_than_hours.nil? ? Cart::RECENT_HOURS : older_than_hours.to_i
      raise Error, "olderThanHours must be between 0 and 720." unless hours.between?(0, 720)

      open_carts(store.carts.stale(hours: hours), limit)
    end

    def active_carts(store, within_hours:, limit:)
      hours = within_hours.nil? ? Cart::RECENT_HOURS : within_hours.to_i
      raise Error, "withinHours must be between 1 and 720." unless hours.between?(1, 720)

      open_carts(store.carts.recent(hours: hours), limit)
    end

    def export_csv(store, kind:)
      kind = kind.to_s
      raise Error, "Export kind must be #{EXPORT_KINDS.join(", ")}." unless EXPORT_KINDS.include?(kind)

      headers, rows = export_table(store, kind)
      truncated = rows.size > MAX_EXPORT
      rows = rows.first(MAX_EXPORT)
      csv = CSV.generate do |out|
        out << headers
        rows.each { |row| out << headers.map { |header| csv_cell(row[header]) } }
      end
      Export.new(csv: csv, rows: rows.size, truncated: truncated)
    end

    def import_csv!(store, kind:, csv:, confirm:)
      raise Error, "Set confirm: true to import." unless confirm

      kind = kind.to_s
      raise Error, "Import kind must be #{IMPORT_KINDS.join(", ")}." unless IMPORT_KINDS.include?(kind)

      table = parse_csv(csv)
      raise Error, "The CSV has no rows." if table.empty?
      raise Error, "Import at most #{MAX_IMPORT} rows at a time." if table.size > MAX_IMPORT

      imported = 0
      errors = []
      table.each_with_index do |row, index|
        import_row!(store, kind, row.to_h)
        imported += 1
      rescue Error => e
        errors << "Row #{index + 2}: #{e.message}"
      end
      Import.new(imported: imported, errors: errors)
    end

    def parse_csv(csv)
      CSV.parse(csv.to_s, headers: true)
    rescue CSV::MalformedCSVError => e
      raise Error, "CSV could not be read: #{e.message}"
    end

    def upsert_section!(store, attrs)
      attrs = attrs.to_h.symbolize_keys
      if attrs[:id].present?
        section = store.home_sections.find_by(id: attrs[:id])
        raise Error, "Section not found: #{attrs[:id]}" unless section
      else
        kind = attrs[:kind].to_s
        raise Error, "kind must be #{HomeSection::KINDS.keys.join(", ")}." unless HomeSection::KINDS.key?(kind)

        section = store.home_sections.new(kind: kind)
      end
      section.visible = attrs[:visible] unless attrs[:visible].nil?
      section.position = attrs[:position] unless attrs[:position].nil?
      section.image_url = attrs[:image_url] unless attrs[:image_url].nil?
      section.link = attrs[:link] if attrs[:link].present?
      section.limit = attrs[:limit] unless attrs[:limit].nil?
      if attrs[:image_position].present?
        raise Error, "imagePosition must be left or right." unless %w[left right].include?(attrs[:image_position])

        section.image_position = attrs[:image_position]
      end
      if attrs[:collection_slug].present?
        collection = store.collections.find_by(slug: attrs[:collection_slug])
        raise Error, "Collection not found: #{attrs[:collection_slug]}" unless collection

        section.collection_id = collection.id
      end
      Translations.assign!(section, attrs[:translations]) if attrs[:translations]
      save!(section)
    end

    def delete_section!(store, id:, confirm:)
      raise Error, "Set confirm: true to delete." unless confirm

      section = store.home_sections.find_by(id: id)
      raise Error, "Section not found: #{id}" unless section

      section.destroy!
      true
    end

    def upsert_page!(store, attrs)
      attrs = attrs.to_h.symbolize_keys
      if attrs[:slug].present?
        page = store.pages.find_by(slug: attrs[:slug])
        raise Error, "Page not found: #{attrs[:slug]}" unless page
        raise Error, "The privacy page is updated from the legal name and contact, not replaced here." if page.slug == "privacy" && attrs[:new_slug].present?
      else
        page = store.pages.new(published: true)
      end
      page.published = attrs[:published] unless attrs[:published].nil?
      page.slug = attrs[:new_slug] if attrs[:new_slug].present?
      Translations.assign!(page, attrs[:translations]) if attrs[:translations]
      raise Error, "A new page needs a fr title." if page.new_record? && page.title.blank?

      save!(page)
    end

    def delete_page!(store, slug:, confirm:)
      raise Error, "Set confirm: true to delete." unless confirm

      page = store.pages.find_by(slug: slug)
      raise Error, "Page not found: #{slug}" unless page
      raise Error, "The privacy page stays. Change the legal name or contact instead." if page.slug == "privacy"

      page.destroy!
      true
    end

    def upsert_menu_item!(store, attrs)
      attrs = attrs.to_h.symbolize_keys
      if attrs[:id].present?
        item = store.menu_items.find_by(id: attrs[:id])
        raise Error, "Menu item not found: #{attrs[:id]}" unless item
      else
        menu = attrs[:menu].to_s
        raise Error, "menu must be header or footer." unless MenuItem::MENUS.key?(menu)
        raise Error, "link is required." if attrs[:link].blank?

        item = store.menu_items.new(menu: menu)
      end
      item.menu = attrs[:menu] if attrs[:menu].present?
      item.link = attrs[:link] if attrs[:link].present?
      item.position = attrs[:position] unless attrs[:position].nil?
      Translations.assign!(item, attrs[:translations]) if attrs[:translations]
      raise Error, "A new menu item needs a fr label." if item.new_record? && item.label.blank?

      save!(item)
    end

    def delete_menu_item!(store, id:, confirm:)
      raise Error, "Set confirm: true to delete." unless confirm

      item = store.menu_items.find_by(id: id)
      raise Error, "Menu item not found: #{id}" unless item

      item.destroy!
      true
    end

    def save!(record)
      return record if record.save

      raise Error, record.errors.full_messages.to_sentence
    end

    def assign_present(record, attrs, *keys)
      keys.each do |key|
        record.public_send("#{key}=", attrs[key]) if attrs[key].present?
      end
    end

    def assign_featured!(store, association, slug, clear, scope)
      if clear
        store.public_send("#{association}=", nil)
      elsif slug.present?
        record = scope.find_by(slug: slug)
        raise Error, "Not found: #{slug}" unless record

        store.public_send("#{association}=", record)
      end
    end

    def normalize_phone(value)
      value.to_s.gsub(/[^\d+]/, "")
    end

    def open_carts(scope, limit)
      scope.includes(cart_items: { product: :translations, product_variant: [] }).limit(clamp(limit))
    end

    def clamp(limit)
      value = limit.to_i
      value = 50 if value <= 0
      value.clamp(1, 100)
    end

    def export_table(store, kind)
      case kind
      when "products"
        headers = %w[slug status priceDh stock sku nameFr nameEn nameAr]
        rows = store.products.includes(:translations).order(:slug).map do |product|
          {
            "slug" => product.slug, "status" => product.status, "priceDh" => product.price_dh,
            "stock" => product.stock, "sku" => product.sku,
            "nameFr" => translation_name(product, "fr"), "nameEn" => translation_name(product, "en"),
            "nameAr" => translation_name(product, "ar")
          }
        end
      when "orders"
        headers = %w[number status createdAt city district totalDh discountCode]
        rows = store.orders.order(created_at: :desc).limit(MAX_EXPORT + 1).map do |order|
          {
            "number" => order.number, "status" => order.status, "createdAt" => order.created_at.iso8601,
            "city" => order.customer_city, "district" => order.customer_district, "totalDh" => order.total_cents / 100,
            "discountCode" => order.discount_code
          }
        end
      when "customers"
        headers = %w[name phone email city ordersCount]
        rows = store.customers.order(:name).map do |customer|
          {
            "name" => customer.name, "phone" => customer.phone, "email" => customer.email,
            "city" => customer.city, "ordersCount" => customer.orders_count
          }
        end
      else
        headers = %w[code type value active startsAt endsAt]
        rows = store.discounts.order(:code).map do |discount|
          {
            "code" => discount.code, "type" => discount.discount_type, "value" => discount.value,
            "active" => discount.active, "startsAt" => discount.starts_at&.iso8601, "endsAt" => discount.ends_at&.iso8601
          }
        end
      end
      [ headers, rows ]
    end

    def translation_name(record, locale)
      record.translations.detect { |item| item.locale == locale }&.name
    end

    def import_row!(store, kind, row)
      case kind
      when "products" then import_product!(store, row)
      when "customers" then import_customer!(store, row)
      else import_discount!(store, row)
      end
    end

    def import_product!(store, row)
      slug = cell(row, "slug")
      raise Error, "slug is required." if slug.blank?

      product = store.products.find_or_initialize_by(slug: slug)
      name_fr = cell(row, "nameFr")
      price = cell(row, "priceDh")
      raise Error, "nameFr is required for a new product." if product.new_record? && name_fr.blank?
      raise Error, "priceDh is required for a new product." if product.new_record? && price.blank?

      product.price_dh = price.to_i if price.present?
      product.status = cell(row, "status") if cell(row, "status").present?
      product.stock = cell(row, "stock").to_i if cell(row, "stock").present?
      product.sku = cell(row, "sku") if row.key?("sku") && !cell(row, "sku").nil?
      entries = [
        [ "fr", name_fr ],
        [ "en", cell(row, "nameEn") ],
        [ "ar", cell(row, "nameAr") ]
      ].filter_map { |locale, name| { locale: locale, name: name } if name.present? }
      Translations.assign!(product, entries)
      product.name = name_fr if product.name.blank?
      save!(product)
    end

    def import_customer!(store, row)
      upsert_customer!(store, phone: cell(row, "phone"), name: cell(row, "name"), email: cell(row, "email"), city: cell(row, "city"))
    end

    def import_discount!(store, row)
      active = cell(row, "active")
      upsert_discount!(
        store,
        code: cell(row, "code"),
        discount_type: cell(row, "type"),
        value: cell(row, "value").presence&.to_i,
        active: active.nil? ? nil : ActiveModel::Type::Boolean.new.cast(active),
        starts_at: parse_time(cell(row, "startsAt")),
        ends_at: parse_time(cell(row, "endsAt"))
      )
    end

    def cell(row, key)
      row[key]&.to_s&.strip
    end

    def parse_time(value)
      return if value.blank?

      Time.zone.parse(value) || raise(Error, "Invalid time #{value}.")
    rescue ArgumentError
      raise Error, "Invalid time #{value}."
    end

    def csv_cell(value)
      text = value.to_s
      text.match?(/\A[=+\-@]/) ? "'#{text}" : value
    end
  end
end
