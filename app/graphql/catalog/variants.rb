# frozen_string_literal: true

module Catalog
  class Variants
    class Error < StandardError; end

    def self.upsert!(product, rows)
      product.transaction do
        Array(rows).each do |row|
          attrs = row.to_h.symbolize_keys
          size = text(attrs[:size])
          color = text(attrs[:color])
          raise Error, "Each variant needs a size or a color" if size.blank? && color.blank?

          variant = product.product_variants.find { |item| item.option_key == [ size.to_s, color.to_s ] }
          variant ||= product.product_variants.new
          was_new = variant.new_record?
          desired_stock = attrs.key?(:stock) ? attrs[:stock].to_i : nil
          assign(variant, attrs, size, color, apply_stock: was_new || !attrs.key?(:stock))
          variant.save!

          if was_new && variant.stock.positive?
            ::Inventory::Adjuster.ledger!(
              product: product,
              variant: variant,
              quantity: variant.stock,
              reason: "received",
              note: "Initial variant stock via set_product_variants"
            )
          elsif !desired_stock.nil? && !was_new
            ::Inventory::Adjuster.set!(
              product: product,
              variant: variant,
              stock: desired_stock,
              reason: "correction",
              note: "Variant stock set via set_product_variants"
            )
          end
        end
      end
      product.product_variants.reset
      product
    rescue ::Inventory::Adjuster::Error => e
      raise Error, e.message
    end

    def self.delete!(product, ids:, keys:, confirm:)
      raise Error, "Set confirm: true to delete." unless confirm

      selected = []
      Array(ids).each do |id|
        variant = product.product_variants.find_by(id: id)
        raise Error, "Unknown variant id: #{id}" unless variant

        selected << variant
      end
      Array(keys).each do |key|
        attrs = key.to_h.symbolize_keys
        size = text(attrs[:size]).to_s
        color = text(attrs[:color]).to_s
        variant = product.product_variants.find { |item| item.option_key == [ size, color ] }
        raise Error, "Unknown variant: #{[ size, color ].compact_blank.join(" / ")}" unless variant

        selected << variant
      end
      raise Error, "Pass variant ids or size and color" if selected.empty?

      product.transaction { selected.uniq.each(&:destroy!) }
      product.product_variants.reset
      product
    end

    def self.assign(variant, attrs, size, color, apply_stock: true)
      variant.option1_name = size.present? ? ProductVariant::SIZE_OPTION_NAME : nil
      variant.option1_value = size
      variant.option2_name = color.present? ? ProductVariant::COLOR_OPTION_NAME : nil
      variant.option2_value = color
      variant.color_hex = color.present? ? ProductVariant.normalize_hex(attrs[:color_hex]) : nil if attrs.key?(:color_hex) || variant.new_record?
      variant.sku = text(attrs[:sku]) if attrs.key?(:sku) || variant.new_record?
      if apply_stock && (attrs.key?(:stock) || variant.new_record?)
        variant.stock = attrs[:stock].nil? ? 0 : attrs[:stock].to_i
      end
      if attrs.key?(:active) || variant.new_record?
        variant.active = attrs.key?(:active) ? ActiveModel::Type::Boolean.new.cast(attrs[:active]) : true
      end
      return unless attrs.key?(:price_dh) || variant.new_record?

      variant.price_cents = attrs[:price_dh].present? ? attrs[:price_dh].to_i * 100 : nil
    end

    def self.text(value)
      value.to_s.strip.presence
    end

    private_class_method :assign, :text
  end
end
