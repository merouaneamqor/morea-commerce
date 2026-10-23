# frozen_string_literal: true

module Admin
  module Variants
    class MediaUpdater
      class Error < StandardError; end

      def self.replace!(variant, selection)
        ids = JSON.parse(selection.to_s)
        raise Error, "Choose up to 100 images." unless ids.is_a?(Array) && ids.size <= 100

        ids = ids.map(&:to_s).uniq
        product = variant.product
        allowed = product.images_attachments.includes(:blob).to_a +
          ActiveStorage::Attachment.where(record_type: "ProductVariant", record_id: product.product_variants.select(:id), name: "images").includes(:blob).to_a
        blobs = allowed.index_by { |attachment| attachment.blob_id.to_s }
        raise Error, "One or more images are no longer available for this product." unless (ids - blobs.keys).empty?

        variant.images = ids.map { |id| blobs.fetch(id).blob }
        variant.save!
        attachments = variant.images_attachments.reload.index_by { |attachment| attachment.blob_id.to_s }
        variant.update!(image_order: ids.map { |id| attachments.fetch(id).id })
      rescue JSON::ParserError
        raise Error, "Invalid image selection. Please select the images again."
      end
    end
  end
end
