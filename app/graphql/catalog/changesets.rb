# frozen_string_literal: true

module Catalog
  module Changesets
    class Error < StandardError; end

    ALLOWED_TYPES = %w[
      create_product
      update_product
      set_product_collections
      create_collection
      update_collection
      set_collection_products
      delete_product
      delete_collection
      update_store_profile
      adjust_stock
      set_stock
    ].freeze

    module_function

    def preview(store, operations:, summary: nil)
      ops = normalize_operations(operations)
      classified = ops.map { |op| classify(store, op) }
      max_level = classified.map { |row| row["level"] }.max || 1

      changeset = store.agent_changesets.create!(
        summary: summary.presence || default_summary(classified),
        operations: ops,
        preview: {
          "operationCount" => classified.size,
          "maxLevel" => max_level,
          "needsApproval" => classified.select { |row| row["level"] > 1 },
          "operations" => classified
        },
        max_level: max_level,
        status: "previewed"
      )

      present(changeset)
    end

    def apply(store, token:, approve_level2: false, approve_level3: false)
      changeset = find!(store, token)
      raise Error, "Changeset already applied" if changeset.applied?
      raise Error, "Changeset was rolled back" if changeset.rolled_back?

      classified = Array(changeset.preview["operations"])
      enforce_approvals!(classified, approve_level2:, approve_level3:)

      snapshots = []
      results = []

      ActiveRecord::Base.transaction do
        changeset.operations.each_with_index do |op, index|
          snapshot, result = apply_one!(store, op.deep_stringify_keys)
          snapshots << snapshot.merge("index" => index)
          results << result.merge("index" => index)
          raise Error, Array(result["errors"]).join(", ") if Array(result["errors"]).any?
        end

        changeset.update!(
          status: "applied",
          snapshots: snapshots,
          results: { "operations" => results },
          applied_at: Time.current
        )
      end

      present(changeset.reload)
    rescue Error, ActiveRecord::RecordInvalid => e
      changeset&.update!(status: "failed", results: { "error" => e.message })
      raise
    end

    def verify(store, token:)
      changeset = find!(store, token)
      raise Error, "Apply the changeset before verifying" unless changeset.applied?

      failures = []
      Array(changeset.operations).each_with_index do |op, index|
        check = verify_one(store, op.deep_stringify_keys)
        failures << check.merge("index" => index) unless check["ok"]
      end

      verification = {
        "ok" => failures.empty?,
        "checked" => changeset.operations.size,
        "failures" => failures
      }
      changeset.update!(
        status: failures.empty? ? "verified" : "applied",
        verification: verification,
        verified_at: Time.current
      )
      present(changeset.reload)
    end

    def rollback(store, token:)
      changeset = find!(store, token)
      raise Error, "Only applied changesets can be rolled back" unless changeset.applied?
      raise Error, "Changeset already rolled back" if changeset.rolled_back?
      raise Error, "No snapshots available for rollback" if Array(changeset.snapshots).empty?

      ActiveRecord::Base.transaction do
        Array(changeset.snapshots).reverse_each do |snapshot|
          restore_one!(store, snapshot.deep_stringify_keys)
        end
        changeset.update!(status: "rolled_back", rolled_back_at: Time.current)
      end

      present(changeset.reload)
    end

    def find!(store, token)
      store.agent_changesets.find_by!(token: token)
    rescue ActiveRecord::RecordNotFound
      raise Error, "Unknown changeset: #{token}"
    end

    def present(changeset)
      {
        token: changeset.token,
        status: changeset.status,
        summary: changeset.summary,
        max_level: changeset.max_level,
        operations: changeset.operations,
        preview: changeset.preview,
        results: changeset.results,
        verification: changeset.verification,
        applied_at: changeset.applied_at&.iso8601,
        verified_at: changeset.verified_at&.iso8601,
        rolled_back_at: changeset.rolled_back_at&.iso8601
      }
    end

    def normalize_operations(operations)
      list = Array(operations).map { |op| op.deep_stringify_keys }
      raise Error, "operations must not be empty" if list.empty?
      raise Error, "At most 100 operations per changeset" if list.size > 100

      list.each do |op|
        type = op["type"].to_s
        raise Error, "Unsupported operation type: #{type}" unless ALLOWED_TYPES.include?(type)
      end
      list
    end

    def classify(store, op)
      type = op["type"].to_s
      level = case type
      when "update_product" then product_update_level(op)
      when "create_product", "adjust_stock", "set_stock" then 2
      when "set_product_collections" then 1
      when "create_collection", "update_collection", "set_collection_products" then 2
      when "delete_product", "delete_collection" then 3
      when "update_store_profile" then 1
      else 2
      end

      {
        "type" => type,
        "level" => level,
        "approval" => level_label(level),
        "target" => op["slug"] || op["keepSlug"] || "store",
        "diff" => preview_diff(store, op),
        "errors" => validate_op(store, op)
      }
    end

    def product_update_level(op)
      attrs = op.fetch("attrs", op).except("type", "slug")
      return 2 if attrs.key?("newSlug") || attrs.key?("priceDh") || attrs.key?("compareAtDh") || attrs.key?("clearCompareAt")
      return 2 if attrs.key?("stock") || attrs.key?("sku")

      1
    end

    def level_label(level)
      { 1 => "automatic", 2 => "preview_first", 3 => "restricted" }.fetch(level)
    end

    def enforce_approvals!(classified, approve_level2:, approve_level3:)
      needs2 = classified.any? { |row| row["level"].to_i == 2 }
      needs3 = classified.any? { |row| row["level"].to_i == 3 }
      raise Error, "Level 2 changes require approveLevel2: true" if needs2 && !approve_level2
      raise Error, "Level 3 changes require approveLevel3: true" if needs3 && !approve_level3

      true
    end

    def default_summary(classified)
      counts = classified.group_by { |row| row["type"] }.transform_values(&:size)
      parts = counts.map { |type, count| "#{count} #{type}" }
      "Apply #{parts.join(', ')}"
    end

    def preview_diff(store, op)
      case op["type"]
      when "create_product"
        { "after" => op.except("type") }
      when "update_product"
        product = store.products.includes(:translations).find_by(slug: op["slug"])
        return { "error" => "Product not found: #{op['slug']}" } unless product

        attrs = op["attrs"] || op.except("type", "slug")
        { "before" => product_snapshot(product), "attrs" => attrs }
      when "adjust_stock", "set_stock"
        product = store.products.includes(:product_variants).find_by(slug: op["slug"])
        return { "error" => "Product not found: #{op['slug']}" } unless product

        {
          "before" => inventory_snapshot(product, op),
          "attrs" => op.except("type")
        }
      when "set_product_collections"
        product = store.products.includes(:collections).find_by(slug: op["slug"])
        return { "error" => "Product not found: #{op['slug']}" } unless product

        { "before" => product.collections.map(&:slug), "after" => Array(op["collectionSlugs"]) }
      when "create_collection"
        { "after" => op.except("type") }
      when "update_collection"
        collection = store.collections.includes(:translations).find_by(slug: op["slug"])
        return { "error" => "Collection not found: #{op['slug']}" } unless collection

        { "before" => collection_snapshot(collection), "attrs" => op["attrs"] || op.except("type", "slug") }
      when "set_collection_products"
        collection = store.collections.includes(:products).find_by(slug: op["slug"])
        return { "error" => "Collection not found: #{op['slug']}" } unless collection

        { "before" => collection.products.map(&:slug), "after" => Array(op["productSlugs"]) }
      when "delete_product", "delete_collection"
        { "slug" => op["slug"], "confirm" => op["confirm"] == true }
      when "update_store_profile"
        { "before" => store.agent_profile, "after" => op["attrs"] || op.except("type") }
      else
        {}
      end
    end

    def validate_op(store, op)
      errors = []
      case op["type"]
      when "create_product"
        errors << "priceDh is required" if op["priceDh"].nil?
        errors << "translations with fr name are required" if Array(op["translations"]).none? { |t| t["locale"] == "fr" && t["name"].present? }
      when "update_product", "set_product_collections", "delete_product", "adjust_stock", "set_stock"
        errors << "Product not found: #{op['slug']}" unless store.products.exists?(slug: op["slug"])
        errors << "delete_product requires confirm: true" if op["type"] == "delete_product" && op["confirm"] != true
        if op["type"] == "adjust_stock"
          errors << "quantity must be a non-zero integer" if op["quantity"].to_i.zero?
          errors << "reason is required" if op["reason"].to_s.strip.blank?
        end
        errors << "stock is required" if op["type"] == "set_stock" && op["stock"].nil?
      when "update_collection", "set_collection_products", "delete_collection"
        errors << "Collection not found: #{op['slug']}" unless store.collections.exists?(slug: op["slug"])
        errors << "delete_collection requires confirm: true" if op["type"] == "delete_collection" && op["confirm"] != true
      when "create_collection"
        errors << "translations with fr name are required" if Array(op["translations"]).none? { |t| t["locale"] == "fr" && t["name"].present? }
      end
      errors
    end

    def apply_one!(store, op)
      case op["type"]
      when "create_product" then apply_create_product!(store, op)
      when "update_product" then apply_update_product!(store, op)
      when "set_product_collections" then apply_set_product_collections!(store, op)
      when "create_collection" then apply_create_collection!(store, op)
      when "update_collection" then apply_update_collection!(store, op)
      when "set_collection_products" then apply_set_collection_products!(store, op)
      when "delete_product" then apply_delete_product!(store, op)
      when "delete_collection" then apply_delete_collection!(store, op)
      when "update_store_profile" then apply_update_profile!(store, op)
      when "adjust_stock" then apply_adjust_stock!(store, op)
      when "set_stock" then apply_set_stock!(store, op)
      else
        raise Error, "Unsupported operation: #{op['type']}"
      end
    end

    def apply_create_product!(store, op)
      product = store.products.new(
        status: op["status"].presence || "draft",
        currency: op["currency"].presence || store.currency,
        stock: op["stock"] || 0,
        track_inventory: op.key?("trackInventory") ? op["trackInventory"] : true,
        featured: op["featured"] || false,
        position: op["position"] || 0,
        sku: op["sku"].presence
      )
      product.price_dh = op["priceDh"]
      product.compare_at_dh = op["compareAtDh"] if op["compareAtDh"]
      product.slug = op["slug"] if op["slug"].present?
      Catalog::Translations.assign!(product, normalize_translations(op["translations"]))
      snapshot = { "type" => "create_product", "slug" => product.slug, "created" => true }

      return [ snapshot, { "ok" => false, "errors" => product.errors.full_messages } ] unless product.save

      if op["collectionSlugs"]
        ids, missing = Catalog::Membership.collection_ids_for(store, op["collectionSlugs"])
        return [ snapshot, { "ok" => false, "errors" => missing.map { |slug| "Unknown collection: #{slug}" } } ] if missing.any?

        Catalog::Membership.apply_collections!(product, ids)
      end
      if product.stock.positive?
        ::Inventory::Adjuster.ledger!(
          product: product,
          quantity: product.stock,
          reason: "received",
          note: "Initial stock via create_product changeset"
        )
      end
      [ snapshot.merge("slug" => product.slug), { "ok" => true, "type" => "create_product", "slug" => product.slug, "errors" => [] } ]
    end

    def apply_update_product!(store, op)
      product = store.products.includes(:translations, :product_variants).find_by!(slug: op["slug"])
      snapshot = { "type" => "update_product", "slug" => product.slug, "before" => product_snapshot(product) }
      attrs = stringify_keys(op["attrs"] || op.except("type", "slug"))
      desired_stock = attrs.key?("stock") ? attrs["stock"] : nil

      product.slug = attrs["newSlug"] if attrs["newSlug"].present?
      product.status = attrs["status"] if attrs["status"].present?
      product.price_dh = attrs["priceDh"] unless attrs["priceDh"].nil?
      product.compare_at_dh = nil if attrs["clearCompareAt"]
      product.compare_at_dh = attrs["compareAtDh"] unless attrs["compareAtDh"].nil?
      product.currency = attrs["currency"] if attrs["currency"].present?
      product.sku = attrs["sku"].presence if attrs.key?("sku") && !attrs["sku"].nil?
      product.track_inventory = attrs["trackInventory"] unless attrs["trackInventory"].nil?
      product.featured = attrs["featured"] unless attrs["featured"].nil?
      product.position = attrs["position"] unless attrs["position"].nil?
      Catalog::Translations.assign!(product, normalize_translations(attrs["translations"])) if attrs["translations"]

      unless product.save
        return [ snapshot, { "ok" => false, "type" => "update_product", "slug" => op["slug"], "errors" => product.errors.full_messages } ]
      end

      if !desired_stock.nil? && product.product_variants.any?
        return [ snapshot, { "ok" => false, "errors" => [ "Product has variants; use set_stock or adjust_stock for variant inventory" ] } ]
      end

      if !desired_stock.nil? && product.product_variants.empty?
        ::Inventory::Adjuster.set!(
          product: product,
          stock: desired_stock,
          reason: "correction",
          note: "Stock set via update_product changeset"
        )
      end

      [ snapshot, { "ok" => true, "type" => "update_product", "slug" => product.slug, "errors" => [] } ]
    rescue ::Inventory::Adjuster::Error => e
      [ snapshot, { "ok" => false, "type" => "update_product", "slug" => op["slug"], "errors" => [ e.message ] } ]
    end

    def apply_adjust_stock!(store, op)
      product = store.products.includes(:product_variants).find_by!(slug: op["slug"])
      snapshot = { "type" => "adjust_stock", "slug" => product.slug, "before" => inventory_snapshot(product, op) }
      result = ::Inventory::Adjuster.adjust!(
        product: product,
        quantity: op["quantity"],
        reason: op["reason"],
        note: op["note"],
        size: op["size"],
        color: op["color"],
        variant_id: op["variantId"]
      )
      [ snapshot, { "ok" => true, "type" => "adjust_stock", "slug" => product.slug, "stock" => result.stock, "errors" => [] } ]
    rescue ::Inventory::Adjuster::Error => e
      [ snapshot, { "ok" => false, "type" => "adjust_stock", "slug" => op["slug"], "errors" => [ e.message ] } ]
    end

    def apply_set_stock!(store, op)
      product = store.products.includes(:product_variants).find_by!(slug: op["slug"])
      snapshot = { "type" => "set_stock", "slug" => product.slug, "before" => inventory_snapshot(product, op) }
      result = ::Inventory::Adjuster.set!(
        product: product,
        stock: op["stock"],
        reason: op["reason"].presence || "correction",
        note: op["note"],
        size: op["size"],
        color: op["color"],
        variant_id: op["variantId"]
      )
      [ snapshot, { "ok" => true, "type" => "set_stock", "slug" => product.slug, "stock" => result.stock, "errors" => [] } ]
    rescue ::Inventory::Adjuster::Error => e
      [ snapshot, { "ok" => false, "type" => "set_stock", "slug" => op["slug"], "errors" => [ e.message ] } ]
    end

    def apply_set_product_collections!(store, op)
      product = store.products.includes(:collections).find_by!(slug: op["slug"])
      snapshot = { "type" => "set_product_collections", "slug" => product.slug, "before" => product.collections.map(&:slug) }
      ids, missing = Catalog::Membership.collection_ids_for(store, op["collectionSlugs"])
      return [ snapshot, { "ok" => false, "errors" => missing.map { |slug| "Unknown collection: #{slug}" } } ] if missing.any?

      Catalog::Membership.apply_collections!(product, ids)
      [ snapshot, { "ok" => true, "type" => "set_product_collections", "slug" => product.slug, "errors" => [] } ]
    end

    def apply_create_collection!(store, op)
      collection = store.collections.new(published: op.key?("published") ? op["published"] : true, position: op["position"] || 0)
      collection.slug = op["slug"] if op["slug"].present?
      Catalog::Translations.assign!(collection, normalize_translations(op["translations"]))
      snapshot = { "type" => "create_collection", "slug" => collection.slug, "created" => true }

      if collection.save
        if op["productSlugs"]
          ids, missing = Catalog::Membership.product_ids_for(store, op["productSlugs"])
          return [ snapshot, { "ok" => false, "errors" => missing.map { |slug| "Unknown product: #{slug}" } } ] if missing.any?

          Catalog::Membership.apply_products!(collection, ids)
        end
        [ snapshot.merge("slug" => collection.slug), { "ok" => true, "type" => "create_collection", "slug" => collection.slug, "errors" => [] } ]
      else
        [ snapshot, { "ok" => false, "errors" => collection.errors.full_messages } ]
      end
    end

    def apply_update_collection!(store, op)
      collection = store.collections.includes(:translations).find_by!(slug: op["slug"])
      snapshot = { "type" => "update_collection", "slug" => collection.slug, "before" => collection_snapshot(collection) }
      attrs = stringify_keys(op["attrs"] || op.except("type", "slug"))

      collection.slug = attrs["newSlug"] if attrs["newSlug"].present?
      collection.published = attrs["published"] unless attrs["published"].nil?
      collection.position = attrs["position"] unless attrs["position"].nil?
      Catalog::Translations.assign!(collection, normalize_translations(attrs["translations"])) if attrs["translations"]

      if collection.save
        [ snapshot, { "ok" => true, "type" => "update_collection", "slug" => collection.slug, "errors" => [] } ]
      else
        [ snapshot, { "ok" => false, "errors" => collection.errors.full_messages } ]
      end
    end

    def apply_set_collection_products!(store, op)
      collection = store.collections.includes(:products).find_by!(slug: op["slug"])
      snapshot = { "type" => "set_collection_products", "slug" => collection.slug, "before" => collection.products.map(&:slug) }
      ids, missing = Catalog::Membership.product_ids_for(store, op["productSlugs"])
      return [ snapshot, { "ok" => false, "errors" => missing.map { |slug| "Unknown product: #{slug}" } } ] if missing.any?

      Catalog::Membership.apply_products!(collection, ids)
      [ snapshot, { "ok" => true, "type" => "set_collection_products", "slug" => collection.slug, "errors" => [] } ]
    end

    def apply_delete_product!(store, op)
      raise Error, "delete_product requires confirm: true" unless op["confirm"] == true

      product = store.products.includes(:translations, :collections).find_by!(slug: op["slug"])
      snapshot = { "type" => "delete_product", "slug" => product.slug, "before" => product_snapshot(product), "deleted" => true }
      begin
        product.destroy!
        [ snapshot, { "ok" => true, "type" => "delete_product", "slug" => op["slug"], "errors" => [] } ]
      rescue ActiveRecord::DeleteRestrictionError
        [ snapshot, { "ok" => false, "errors" => [ "Product is on an order and cannot be deleted" ] } ]
      end
    end

    def apply_delete_collection!(store, op)
      raise Error, "delete_collection requires confirm: true" unless op["confirm"] == true

      collection = store.collections.includes(:translations, :products).find_by!(slug: op["slug"])
      snapshot = { "type" => "delete_collection", "slug" => collection.slug, "before" => collection_snapshot(collection), "productSlugs" => collection.products.map(&:slug), "deleted" => true }
      collection.destroy!
      [ snapshot, { "ok" => true, "type" => "delete_collection", "slug" => op["slug"], "errors" => [] } ]
    end

    def apply_update_profile!(store, op)
      before = store.agent_profile.deep_dup
      attrs = stringify_keys(op["attrs"] || op.except("type"))
      Autonomy.merge_profile!(store, attrs)
      snapshot = { "type" => "update_store_profile", "before" => before }
      [ snapshot, { "ok" => true, "type" => "update_store_profile", "errors" => [] } ]
    end

    def verify_one(store, op)
      case op["type"]
      when "create_product"
        slug = op["slug"].presence
        if slug
          store.products.exists?(slug: slug) ? ok_check(op) : fail_check(op, "Product was not created")
        else
          ok_check(op)
        end
      when "update_product"
        product = store.products.includes(:translations).find_by(slug: op["newSlug"].presence || op.dig("attrs", "newSlug").presence || op["slug"])
        return fail_check(op, "Product missing after update") unless product

        attrs = (op["attrs"] || op.except("type", "slug")).deep_stringify_keys
        if attrs["priceDh"] && product.price_dh != attrs["priceDh"].to_i
          return fail_check(op, "priceDh expected #{attrs['priceDh']} got #{product.price_dh}")
        end
        if attrs["status"] && product.status != attrs["status"]
          return fail_check(op, "status expected #{attrs['status']} got #{product.status}")
        end
        if attrs.key?("stock") && product.product_variants.empty? && product.stock != attrs["stock"].to_i
          return fail_check(op, "stock expected #{attrs['stock']} got #{product.stock}")
        end
        ok_check(op)
      when "adjust_stock", "set_stock"
        product = store.products.includes(:product_variants).find_by(slug: op["slug"])
        return fail_check(op, "Product missing") unless product

        target = inventory_target(product, op)
        return fail_check(op, "Variant not found") unless target

        if op["type"] == "set_stock" && target.stock != op["stock"].to_i
          return fail_check(op, "stock expected #{op['stock']} got #{target.stock}")
        end
        ok_check(op)
      when "set_product_collections"
        product = store.products.includes(:collections).find_by(slug: op["slug"])
        return fail_check(op, "Product missing") unless product

        actual = product.collections.map(&:slug)
        expected = Array(op["collectionSlugs"])
        actual == expected ? ok_check(op) : fail_check(op, "collections expected #{expected} got #{actual}")
      when "create_collection"
        store.collections.exists?(slug: op["slug"]) ? ok_check(op) : fail_check(op, "Collection was not created")
      when "update_collection"
        slug = op.dig("attrs", "newSlug").presence || op["slug"]
        store.collections.exists?(slug: slug) ? ok_check(op) : fail_check(op, "Collection missing after update")
      when "set_collection_products"
        collection = store.collections.includes(:products).find_by(slug: op["slug"])
        return fail_check(op, "Collection missing") unless collection

        actual = collection.products.map(&:slug)
        expected = Array(op["productSlugs"])
        actual == expected ? ok_check(op) : fail_check(op, "products expected #{expected} got #{actual}")
      when "delete_product"
        store.products.exists?(slug: op["slug"]) ? fail_check(op, "Product still exists") : ok_check(op)
      when "delete_collection"
        store.collections.exists?(slug: op["slug"]) ? fail_check(op, "Collection still exists") : ok_check(op)
      when "update_store_profile"
        ok_check(op)
      else
        fail_check(op, "Unknown operation")
      end
    end

    def restore_one!(store, snapshot)
      case snapshot["type"]
      when "create_product"
        store.products.find_by(slug: snapshot["slug"])&.destroy!
      when "update_product"
        product = store.products.includes(:translations).find_by(slug: snapshot.dig("before", "slug")) ||
          store.products.includes(:translations).find_by(slug: snapshot["slug"])
        raise Error, "Cannot rollback missing product #{snapshot['slug']}" unless product

        restore_product!(product, snapshot["before"])
      when "adjust_stock", "set_stock"
        product = store.products.includes(:product_variants).find_by!(slug: snapshot["slug"])
        before = snapshot["before"] || {}
        target = if before["variantId"].present?
          product.product_variants.find_by(id: before["variantId"])
        elsif before["size"].present? || before["color"].present?
          ::Inventory::Adjuster.resolve_variant!(product, size: before["size"], color: before["color"])
        else
          product
        end
        raise Error, "Cannot rollback inventory for missing target on #{snapshot['slug']}" unless target

        ::Inventory::Adjuster.set!(
          product: product,
          variant: (target == product ? nil : target),
          stock: before.fetch("stock"),
          reason: "correction",
          note: "Rollback changeset inventory"
        )
      when "set_product_collections"
        product = store.products.find_by!(slug: snapshot["slug"])
        ids, = Catalog::Membership.collection_ids_for(store, snapshot["before"])
        Catalog::Membership.apply_collections!(product, ids)
      when "create_collection"
        store.collections.find_by(slug: snapshot["slug"])&.destroy!
      when "update_collection"
        collection = store.collections.includes(:translations).find_by(slug: snapshot.dig("before", "slug")) ||
          store.collections.includes(:translations).find_by(slug: snapshot["slug"])
        raise Error, "Cannot rollback missing collection #{snapshot['slug']}" unless collection

        restore_collection!(collection, snapshot["before"])
      when "set_collection_products"
        collection = store.collections.find_by!(slug: snapshot["slug"])
        ids, = Catalog::Membership.product_ids_for(store, snapshot["before"])
        Catalog::Membership.apply_products!(collection, ids)
      when "delete_product"
        raise Error, "Cannot recreate deleted product #{snapshot['slug']} automatically. Restore from snapshot data manually." if snapshot["deleted"]
      when "delete_collection"
        raise Error, "Cannot recreate deleted collection #{snapshot['slug']} automatically." if snapshot["deleted"]
      when "update_store_profile"
        store.update!(agent_profile: snapshot["before"] || {})
      else
        raise Error, "Cannot rollback operation #{snapshot['type']}"
      end
    end

    def restore_product!(product, before)
      previous_stock = product.stock
      product.slug = before["slug"]
      product.status = before["status"]
      product.price_dh = before["priceDh"]
      product.compare_at_dh = before["compareAtDh"]
      product.currency = before["currency"]
      product.sku = before["sku"]
      product.track_inventory = before["trackInventory"]
      product.featured = before["featured"]
      product.position = before["position"]
      Catalog::Translations.assign!(product, normalize_translations(before["translations"]))
      product.save!
      return if product.product_variants.any?
      return if before["stock"].nil? || before["stock"].to_i == previous_stock

      ::Inventory::Adjuster.set!(
        product: product,
        stock: before["stock"],
        reason: "correction",
        note: "Rollback product stock"
      )
    end

    def restore_collection!(collection, before)
      collection.slug = before["slug"]
      collection.published = before["published"]
      collection.position = before["position"]
      Catalog::Translations.assign!(collection, normalize_translations(before["translations"]))
      collection.save!
    end

    def stringify_keys(value)
      case value
      when Hash then value.deep_stringify_keys
      else {}
      end
    end

    def normalize_translations(entries)
      Array(entries).map do |entry|
        row = entry.deep_stringify_keys
        {
          locale: row["locale"],
          name: row["name"],
          short_description: row["shortDescription"] || row["short_description"],
          story: row["story"],
          material: row["material"],
          fit: row["fit"],
          movement: row["movement"],
          dimensions: row["dimensions"],
          origin: row["origin"],
          care: row["care"],
          seo_title: row["seoTitle"] || row["seo_title"],
          seo_description: row["seoDescription"] || row["seo_description"],
          subtitle: row["subtitle"],
          description: row["description"]
        }.compact
      end
    end

    def product_snapshot(product)
      {
        "slug" => product.slug,
        "status" => product.status,
        "priceDh" => product.price_dh,
        "compareAtDh" => product.compare_at_dh,
        "currency" => product.currency,
        "sku" => product.sku,
        "stock" => product.stock,
        "trackInventory" => product.track_inventory,
        "featured" => product.featured,
        "position" => product.position,
        "collectionSlugs" => product.collections.map(&:slug),
        "translations" => product.translations.map do |translation|
          {
            "locale" => translation.locale,
            "name" => translation.name,
            "shortDescription" => translation.short_description,
            "story" => translation.story,
            "material" => translation.material,
            "fit" => translation.fit,
            "movement" => translation.movement,
            "dimensions" => translation.dimensions,
            "origin" => translation.origin,
            "care" => translation.care,
            "seoTitle" => translation.seo_title,
            "seoDescription" => translation.seo_description
          }
        end
      }
    end

    def inventory_snapshot(product, op)
      target = inventory_target(product, op)
      {
        "slug" => product.slug,
        "stock" => target&.stock,
        "size" => op["size"],
        "color" => op["color"],
        "variantId" => op["variantId"].presence || (target.is_a?(ProductVariant) ? target.id.to_s : nil)
      }
    end

    def inventory_target(product, op)
      if op["variantId"].present? || op["size"].present? || op["color"].present?
        ::Inventory::Adjuster.resolve_variant!(
          product,
          size: op["size"],
          color: op["color"],
          variant_id: op["variantId"]
        )
      else
        product
      end
    rescue ::Inventory::Adjuster::Error
      nil
    end

    def collection_snapshot(collection)
      {
        "slug" => collection.slug,
        "published" => collection.published,
        "position" => collection.position,
        "productSlugs" => collection.products.map(&:slug),
        "translations" => collection.translations.map do |translation|
          {
            "locale" => translation.locale,
            "name" => translation.name,
            "subtitle" => translation.subtitle,
            "description" => translation.description
          }
        end
      }
    end

    def ok_check(op)
      { "ok" => true, "type" => op["type"], "slug" => op["slug"] }
    end

    def fail_check(op, message)
      { "ok" => false, "type" => op["type"], "slug" => op["slug"], "error" => message }
    end
  end
end
