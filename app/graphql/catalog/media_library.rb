# frozen_string_literal: true

module Catalog
  module MediaLibrary
    class Error < StandardError; end
    module_function

    def scope(store)
      ActiveStorage::Attachment.where(name: "images", record_type: "Product", record_id: store.products.select(:id))
    end

    def list(store, page: 1, per_page: 30, product_slug: nil)
      raise Error, "page must be positive and perPage must be between 1 and 100." unless page.to_i.positive? && per_page.to_i.between?(1, 100)

      attachments = scope(store).includes(:blob, :record).order(:id)
      if product_slug.present?
        product = store.products.find_by(slug: product_slug)
        raise Error, "Product not found in this store." unless product

        attachments = attachments.where(record_id: product.id)
      end
      total = attachments.count
      rows = attachments.offset((page.to_i - 1) * per_page.to_i).limit(per_page.to_i)
      { "page" => page.to_i, "perPage" => per_page.to_i, "total" => total,
        "hasMore" => page.to_i * per_page.to_i < total,
        "images" => rows.map { |attachment| describe(attachment).merge("url" => Catalog::Images.absolute_url(attachment, store)) } }
    end

    def edit!(store, attachment_ids:, edit:, confirm:)
      raise Error, "Set confirm: true to edit images." unless confirm == true
      raise Error, "Unknown image edit." unless edit == "clear" || MediaUrl::EDITS.key?(edit)
      unless attachment_ids.is_a?(Array) && attachment_ids.size.between?(1, 100) && attachment_ids.all? { |id| id.to_s.match?(/\A[1-9]\d*\z/) }
        raise Error, "Provide 1-100 positive attachment IDs."
      end
      ids = attachment_ids.map(&:to_i).uniq
      attachments = scope(store).where(id: ids).includes(:blob, :record).to_a
      raise Error, "One or more image IDs do not belong to this store's products." unless attachments.size == ids.size
      raise Error, "Image transformations require Cloudinary storage. No images changed." unless attachments.all? { |attachment| MediaUrl.cloudinary?(attachment.blob) }

      blobs = attachments.map(&:blob).uniq(&:id)
      blob_ids = blobs.map(&:id)
      if ActiveStorage::Attachment.where(blob_id: blob_ids).where.not(id: scope(store).select(:id)).exists?
        raise Error, "A source image is shared outside this store's product library. No images changed."
      end
      ActiveRecord::Base.transaction do
        blobs.sort_by(&:id).each do |blob|
          blob.with_lock { MediaUrl.apply!(blob, edit) }
        end
      end
      blobs.each { |blob| MediaWarmupJob.perform_later(blob.id, store.id) } if edit == "remove_bg"
      { "edit" => edit, "processing" => edit == "remove_bg", "images" => attachments.map { |attachment| describe(attachment) } }
    end

    def describe(attachment)
      product = attachment.record
      order = Array(product.image_order)
      position = order.index(attachment.id) || product.ordered_images.index { |image| image.id == attachment.id }
      { "id" => attachment.id.to_s, "productSlug" => product.slug, "filename" => attachment.filename.to_s,
        "position" => position, "storage" => attachment.blob.service_name,
        "edits" => MediaUrl.edits(attachment.blob), "editable" => MediaUrl.cloudinary?(attachment.blob) }
    end
  end
end
