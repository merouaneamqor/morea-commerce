# frozen_string_literal: true

class ProductColorVariantJob < ApplicationJob
  queue_as :default

  retry_on Recolor::Unavailable, wait: 30.seconds, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(product_color_variant_id)
    record = ProductColorVariant.find(product_color_variant_id)
    record.processing!

    attachment = ActiveStorage::Attachment.find_by(
      id: record.source_attachment_id,
      record_type: "Product",
      record_id: record.product_id,
      name: "images"
    )
    unless attachment
      record.mark_failed!("Source image not found")
      return
    end

    image_bytes = attachment.download
    client = Recolor::Client.new
    png = client.recolor(image_bytes: image_bytes, hex_color: record.normalized_hex)

    record.result_image.attach(
      io: StringIO.new(png),
      filename: "color-#{ record.normalized_hex.delete('#') }.png",
      content_type: "image/png"
    )
    record.mark_ready!
  rescue Recolor::Error => e
    record.mark_failed!(e.message)
  end
end
