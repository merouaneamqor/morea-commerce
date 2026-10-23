# frozen_string_literal: true

module Admin
  module Variants
    # Persists the admin variant matrix: destroy selected rows, upsert by size×color key.
    # Save alone must not recreate destroyed variants; Generate can re-add combos later.
    class BulkUpdater
      Result = Struct.new(:ok, :message, keyword_init: true) do
        def success?
          ok
        end
      end

      def initialize(product:, rows:, destroy_ids: [])
        @product = product
        @rows = Array(rows)
        @destroy_ids = Array(destroy_ids).map(&:to_i).reject(&:zero?)
      end

      def call
        existing_by_key = @product.product_variants.index_by(&:option_key)

        ActiveRecord::Base.transaction do
          destroy_marked!(existing_by_key)
          upsert_rows!(existing_by_key)
        end

        Result.new(ok: true, message: "Variants saved.")
      rescue ActiveRecord::RecordInvalid => e
        Result.new(ok: false, message: e.record.errors.full_messages.to_sentence)
      rescue MediaUpdater::Error => e
        Result.new(ok: false, message: e.message)
      end

      private

      def destroy_marked!(existing_by_key)
        @destroy_ids.each do |id|
          variant = @product.product_variants.find_by(id: id)
          next unless variant

          existing_by_key.delete(variant.option_key)
          variant.destroy!
        end
      end

      def upsert_rows!(existing_by_key)
        seen_keys = Set.new

        @rows.each do |row|
          row = row.with_indifferent_access
          attrs = normalize_row(row)
          key = [ attrs[:option1_value].to_s, attrs[:option2_value].to_s ]
          next if key.all?(&:blank?)
          next if seen_keys.include?(key)

          seen_keys << key

          row_id = row[:id].to_i
          # Row still pointing at a destroyed id (stale DOM) — do not recreate.
          next if row_id.positive? && @destroy_ids.include?(row_id)

          variant = row_id.positive? ? @product.product_variants.find_by(id: row_id) : nil
          variant ||= existing_by_key[key]

          # Drop stale in-memory records left over from destroy (or identity-map quirks).
          if variant && (@destroy_ids.include?(variant.id) || variant.destroyed? || !variant.persisted?)
            variant = nil
          end

          variant ||= @product.product_variants.new
          existing_by_key[key] = variant
          variant.assign_attributes(attrs)
          variant.save!
          MediaUpdater.replace!(variant, row[:media_blob_ids]) if row.key?(:media_blob_ids)
        end
      end

      def normalize_row(row)
        row = row.with_indifferent_access
        size = row[:option1_value].to_s.strip.presence
        color = row[:option2_value].to_s.strip.presence
        price_dh = row[:price_dh]
        active_val = row[:active]
        active_val = active_val.last if active_val.is_a?(Array)

        {
          option1_name: size ? ProductVariant::SIZE_OPTION_NAME : nil,
          option1_value: size,
          option2_name: color ? ProductVariant::COLOR_OPTION_NAME : nil,
          option2_value: color,
          color_hex: color ? ProductVariant.normalize_hex(row[:color_hex]) : nil,
          sku: row[:sku].to_s.strip.presence,
          stock: row[:stock].presence || 0,
          active: ActiveModel::Type::Boolean.new.cast(active_val.nil? ? false : active_val),
          price_cents: price_dh.present? ? price_dh.to_i * 100 : nil
        }
      end
    end
  end
end
