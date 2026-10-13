# frozen_string_literal: true

module Inventory
  class Adjuster
    class Error < StandardError; end

    MANUAL_REASONS = InventoryMovement::MANUAL_REASONS
    ORDER_REASONS = InventoryMovement::ORDER_REASONS
    ALL_REASONS = InventoryMovement::REASONS

    Result = Data.define(:product, :movement, :previous_stock, :stock)

    def self.adjust!(product:, quantity:, reason:, note: nil, variant: nil, order: nil, size: nil, color: nil, variant_id: nil)
      new(product).adjust!(
        quantity: quantity,
        reason: reason,
        note: note,
        variant: variant,
        order: order,
        size: size,
        color: color,
        variant_id: variant_id
      )
    end

    def self.set!(product:, stock:, reason: "correction", note: nil, variant: nil, size: nil, color: nil, variant_id: nil)
      new(product).set!(
        stock: stock,
        reason: reason,
        note: note,
        variant: variant,
        size: size,
        color: color,
        variant_id: variant_id
      )
    end

    def self.ledger!(product:, quantity:, reason:, note: nil, variant: nil, order: nil)
      qty = Integer(quantity)
      raise Error, "Quantity must be a non-zero integer." if qty.zero?

      product.inventory_movements.create!(
        product_variant: variant,
        order: order,
        quantity: qty,
        reason: normalize_reason!(reason),
        note: note.to_s.strip.presence
      )
    end

    def self.normalize_reason!(reason)
      key = reason.to_s.strip.presence || "manual_adjustment"
      return key if ALL_REASONS.include?(key)

      raise Error, "Unknown reason: #{key}. Use one of #{MANUAL_REASONS.join(', ')}."
    end

    def self.resolve_variant!(product, variant: nil, size: nil, color: nil, variant_id: nil)
      return variant if variant
      return product.product_variants.find(variant_id) if variant_id.present?

      size_value = size.to_s.strip.presence
      color_value = color.to_s.strip.presence
      return nil if size_value.blank? && color_value.blank?

      scope = product.product_variants
      scope = scope.where(option1_value: size_value) if size_value
      scope = scope.where(option2_value: color_value) if color_value
      matches = scope.to_a
      raise Error, "Variant not found for size=#{size_value.inspect} color=#{color_value.inspect}" if matches.empty?
      raise Error, "Multiple variants match size=#{size_value.inspect} color=#{color_value.inspect}" if matches.size > 1

      matches.first
    rescue ActiveRecord::RecordNotFound
      raise Error, "Variant not found: #{variant_id}"
    end

    def initialize(product)
      @product = product
    end

    def adjust!(quantity:, reason:, note: nil, variant: nil, order: nil, size: nil, color: nil, variant_id: nil)
      qty = Integer(quantity)
      raise Error, "Quantity must be a non-zero integer." if qty.zero?

      reason_key = self.class.normalize_reason!(reason)
      target_variant = self.class.resolve_variant!(
        @product,
        variant: variant,
        size: size,
        color: color,
        variant_id: variant_id
      )
      require_variant_target!(target_variant)
      target = target_variant || @product
      previous = target.stock
      new_stock = previous + qty
      raise Error, "Stock cannot go below zero." if new_stock.negative?

      movement = nil
      ActiveRecord::Base.transaction do
        target.update!(stock: new_stock)
        movement = @product.inventory_movements.create!(
          product_variant: target_variant,
          order: order,
          quantity: qty,
          reason: reason_key,
          note: note.to_s.strip.presence
        )
      end

      Result.new(product: @product.reload, movement: movement, previous_stock: previous, stock: new_stock)
    end

    def set!(stock:, reason: "correction", note: nil, variant: nil, size: nil, color: nil, variant_id: nil)
      absolute = Integer(stock)
      raise Error, "Stock cannot go below zero." if absolute.negative?

      target_variant = self.class.resolve_variant!(
        @product,
        variant: variant,
        size: size,
        color: color,
        variant_id: variant_id
      )
      require_variant_target!(target_variant)
      target = target_variant || @product
      delta = absolute - target.stock
      return Result.new(product: @product, movement: nil, previous_stock: target.stock, stock: absolute) if delta.zero?

      adjust!(
        quantity: delta,
        reason: reason.presence || "correction",
        note: note.presence || "Set stock to #{absolute}",
        variant: target_variant
      )
    end

    private

    def require_variant_target!(target_variant)
      return if target_variant
      return if @product.product_variants.empty?

      raise Error, "Product has variants; pass size+color or variantId to target one."
    end
  end
end
