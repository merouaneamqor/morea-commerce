# frozen_string_literal: true

require "bigdecimal"

module Orders
  # Internal connector boundary, not a public unauthenticated order endpoint.
  # Resolve the store and authorize its caller before invoking this service.
  class Intake
    class Error < StandardError; end
    Result = Struct.new(:order, :created, keyword_init: true) do
      def created? = created
      def replayed? = !created
    end

    CONTACT_FIELDS = %w[name phone phone_country city district address notes tags shipping_dh discount_dh discount_code lines].freeze
    LINE_FIELDS = %w[product_id product_variant_id quantity].freeze
    TEXT_FIELDS = %w[name phone phone_country city district address notes discount_code].freeze
    MAX_MONEY_CENTS = 2_147_483_647 # Current order monetary columns are signed SQL integers.

    def initialize(store:, user: nil)
      raise Error, "A persisted store is required." unless store.is_a?(Store) && store.persisted?
      if user && (!user.persisted? || (!user.super_admin? && user.store_id != store.id))
        raise Error, "The caller does not belong to this store."
      end

      @store = store
      @user = user
    end

    def call(source:, external_id:, attrs:)
      source = identity(source, "source", maximum: 64).downcase
      raise Error, "Source must contain only letters, digits, underscores and hyphens." unless source.match?(/\A[a-z0-9][a-z0-9_-]*\z/)
      external_id = identity(external_id, "external ID", maximum: 255)

      # Locking one tenant row serializes identical concurrent deliveries and also
      # makes identity creation + customer/order/items atomic. The unique index
      # is the final protection against writers that do not use this service.
      @store.with_lock do
        existing = OrderImport.find_by(store: @store, source: source, external_id: external_id)
        return Result.new(order: existing.order, created: false) if existing

        fields = validate_attrs(attrs)
        editor = Editor.new(store: @store, user: @user, external_effects: false)
        order = editor.create(fields)
        unless order
          messages = editor.errors.map do |error|
            [ (error.attribute.to_s.humanize unless error.attribute == :base), error.message ].compact.join(" ")
          end
          raise Error, messages.to_sentence
        end

        OrderImport.create!(store: @store, order: order, source: source, external_id: external_id)
        order.record_event!("comment", body: "Imported from #{source}", user: @user)
        Result.new(order: order, created: true)
      end
    rescue ActiveRecord::RecordNotUnique
      # A connector outside this service may have inserted the identity while
      # this request was being built. The failed transaction is already rolled
      # back here, so never return its unpersisted duplicate order.
      existing = OrderImport.find_by(store: @store, source: source, external_id: external_id)
      raise unless existing

      Result.new(order: existing.order, created: false)
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    rescue ActiveRecord::RangeError
      raise Error, "A numeric value is outside the supported range."
    end

    private

    def identity(value, label, maximum:)
      raise Error, "#{label.capitalize} must be a string." unless value.is_a?(String)

      text = value.strip
      if text.blank? || text.length > maximum || text.match?(/[[:cntrl:]]/)
        raise Error, "#{label.capitalize} must contain 1–#{maximum} printable characters."
      end
      text
    end

    def validate_attrs(attrs)
      raise Error, "Order attributes must be an object." unless attrs.is_a?(Hash)

      fields = attrs.with_indifferent_access
      unknown = fields.keys - CONTACT_FIELDS
      raise Error, "Unknown order fields: #{unknown.join(', ')}" if unknown.any?
      TEXT_FIELDS.each do |field|
        value = fields[field]
        raise Error, "#{field} must be text." unless value.nil? || value.is_a?(String)
      end
      tags = fields[:tags]
      unless tags.nil? || tags.is_a?(String) || (tags.is_a?(Array) && tags.all? { |tag| tag.is_a?(String) })
        raise Error, "Tags must be text or a list of text values."
      end
      raise Error, "Provide between 1 and 100 lines." unless fields[:lines].is_a?(Array) && fields[:lines].size.between?(1, 100)

      fields[:lines].each do |raw|
        raise Error, "Each line must be an object." unless raw.is_a?(Hash)

        line = raw.with_indifferent_access
        raise Error, "Unknown line fields." if (line.keys - LINE_FIELDS).any?
        raise Error, "Quantity must be a positive integer." unless positive_integer?(line[:quantity])
        raise Error, "Product ID must be a positive integer." unless positive_integer?(line[:product_id])
        product = @store.products.active.find_by(id: line[:product_id])
        raise Error, "Unknown or inactive product." unless product

        if line[:product_variant_id].present?
          raise Error, "Variant ID must be a positive integer." unless positive_integer?(line[:product_variant_id])
          raise Error, "Unknown or inactive variant." unless product.product_variants.active.exists?(id: line[:product_variant_id])
        elsif product.product_variants.exists?
          raise Error, "Select a variant for this product."
        end
      end
      %i[shipping_dh discount_dh].each do |field|
        next unless fields.key?(field)

        value = fields[field].to_s
        raise Error, "#{field} must be a non-negative amount with at most two decimals." unless value.match?(/\A\d+(?:\.\d{1,2})?\z/)
        # Check the decimal before Editor converts to Float: an enormous string
        # otherwise becomes Infinity and raises FloatDomainError before the DB.
        cents = BigDecimal(value) * 100
        raise Error, "#{field} is outside the supported monetary range." if cents > MAX_MONEY_CENTS
      end
      fields
    end

    def positive_integer?(value)
      (value.is_a?(Integer) && value.positive?) || (value.is_a?(String) && value.match?(/\A[1-9]\d*\z/))
    end
  end
end
