module Admin
  # Media library: bulk upload images to several products at once, and batch-edit them
  class MediaController < BaseController
    def index
      @products = current_store.products.includes(:translations, images_attachments: :blob).order(:position, :name)
      @product_options = @products.map { |p| { id: p.id, slug: p.slug, name: p.name } }
    end

    def upload
      files = Array(params[:files])
      product_ids = Array(params[:product_ids])
      products = current_store.products.where(id: product_ids.compact_blank).index_by(&:id)

      assignments = files.zip(product_ids).filter_map do |file, product_id|
        product = products[product_id.to_i]
        [ product, file ] if product && file.respond_to?(:content_type) && file.content_type.to_s.start_with?("image/")
      end

      assignments.group_by(&:first).each do |product, pairs|
        uploads = pairs.map(&:last).sort_by { |f| natural_key(f.original_filename) }
        product.images.attach(uploads)
        ids = product.images_attachments.reload.order(:id).ids
        product.update_column(:image_order, (product.image_order & ids) + (ids - product.image_order))
      end

      skipped = files.size - assignments.size
      notice = "#{assignments.size} #{"image".pluralize(assignments.size)} added to #{assignments.map(&:first).uniq.size} #{"product".pluralize(assignments.map(&:first).uniq.size)}."
      notice += " #{skipped} skipped (no product chosen or not an image)." if skipped.positive?
      redirect_to admin_media_path, notice: notice
    end

    def edits
      edit = params[:edit].to_s
      return redirect_to(admin_media_path, alert: "Unknown edit.") unless edit == "clear" || MediaUrl::EDITS.key?(edit)

      attachments = ActiveStorage::Attachment.includes(:blob)
                                             .where(id: Array(params[:attachment_ids]), name: "images", record_type: "Product",
                                                    record_id: current_store.products.select(:id))
      cloud, local = attachments.partition { |a| MediaUrl.cloudinary?(a.blob) }
      cloud.each { |a| MediaUrl.apply!(a.blob, edit) }
      cloud.each { |a| MediaWarmupJob.perform_later(a.blob_id, current_store.id) } if edit == "remove_bg"

      label = edit == "clear" ? "Edits cleared" : "#{MediaUrl::EDITS[edit]} applied"
      notice = "#{label} on #{cloud.size} #{"image".pluralize(cloud.size)}."
      notice += " #{local.size} stored on local disk can't be edited — re-upload them." if local.any?
      notice += " Background removal can take a few seconds to appear." if edit == "remove_bg" && cloud.any?
      redirect_to admin_media_path, notice: notice
    end

    private

    # "look-2.jpg" before "look-10.jpg"
    def natural_key(filename)
      filename.to_s.downcase.split(/(\d+)/).map { |part| part.match?(/\A\d+\z/) ? part.to_i : part }
    end
  end
end
