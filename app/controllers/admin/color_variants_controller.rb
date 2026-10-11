# frozen_string_literal: true

module Admin
  class ColorVariantsController < BaseController
    before_action :set_product
    before_action :set_color_variant, only: %i[attach_to_product assign_variant destroy]

    def create
      attachment = @product.images_attachments.find_by(id: params[:source_attachment_id])
      unless attachment
        redirect_to edit_admin_product_path(@product), alert: "Choose a product image first."
        return
      end

      hex = normalize_hex(params[:hex_color])
      unless hex
        redirect_to edit_admin_product_path(@product), alert: "Enter a valid hex color (e.g. #F4C2C2)."
        return
      end

      record = @product.product_color_variants.create!(
        source_attachment_id: attachment.id,
        hex_color: hex,
        status: "pending"
      )
      ProductColorVariantJob.perform_later(record.id)
      redirect_to edit_admin_product_path(@product), notice: "Generating #{ hex } preview — refresh in a few seconds."
    end

    def attach_to_product
      unless @color_variant.ready? && @color_variant.result_image.attached?
        redirect_to edit_admin_product_path(@product), alert: "Preview is not ready yet."
        return
      end

      @product.images.attach(@color_variant.result_image.blob)
      ids = @product.images_attachments.reload.order(:id).ids
      @product.update_column(:image_order, (@product.image_order & ids) + (ids - @product.image_order))
      redirect_to edit_admin_product_path(@product), notice: "Added recolored image to product gallery."
    end

    def assign_variant
      variant = @product.product_variants.find_by(id: params[:product_variant_id])
      unless variant
        redirect_to edit_admin_product_path(@product), alert: "Variant not found."
        return
      end
      unless @color_variant.ready? && @color_variant.result_image.attached?
        redirect_to edit_admin_product_path(@product), alert: "Preview is not ready yet."
        return
      end

      variant.image.attach(@color_variant.result_image.blob)
      @color_variant.update!(product_variant: variant)
      redirect_to edit_admin_product_path(@product), notice: "Assigned preview to variant #{ variant.display_name }."
    end

    def destroy
      @color_variant.destroy
      redirect_to edit_admin_product_path(@product), notice: "Removed color preview."
    end

    private

    def set_product
      @product = current_store.products.find(params[:product_id])
    end

    def set_color_variant
      @color_variant = @product.product_color_variants.find(params[:id])
    end

    def normalize_hex(value)
      raw = value.to_s.strip
      return ProductColorVariant::PRESET_COLORS[raw] if ProductColorVariant::PRESET_COLORS.key?(raw)
      raw = "##{ raw }" unless raw.start_with?("#")
      return raw if raw.match?(/\A#[0-9A-Fa-f]{3}\z/) || raw.match?(/\A#[0-9A-Fa-f]{6}\z/)

      nil
    end
  end
end
