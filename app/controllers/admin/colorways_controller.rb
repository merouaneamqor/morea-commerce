# frozen_string_literal: true

require "stringio"

module Admin
  # Preview and save a recolored garment without touching the rest of the photo.
  class ColorwaysController < BaseController
    before_action :set_product

    def preview
      result = recolor_source!
      render json: {
        image: data_url(result.image),
        mask: data_url(result.mask),
        report: result.report
      }
    rescue Recolor::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def create
      result = recolor_source!
      colorway = @product.product_colorways.find_or_initialize_by(source_attachment: source_attachment, hex: parsed_hex)
      colorway.assign_attributes(name: parsed_name, prompt: parsed_prompt, points: parsed_points, report: result.report)
      filename = "colorway-#{parsed_name.parameterize.presence || "color"}.png"
      colorway.image.attach(io: StringIO.new(result.image), filename: filename, content_type: "image/png")
      colorway.mask.attach(
        io: StringIO.new(result.mask),
        filename: filename.sub(/\.png\z/, "-mask.png"),
        content_type: "image/png"
      )
      colorway.save!
      redirect_to edit_admin_product_path(@product), notice: "#{colorway.name} saved. The rest of the photo is unchanged."
    rescue Recolor::Error => e
      redirect_to edit_admin_product_path(@product), alert: e.message
    rescue ActiveRecord::RecordInvalid => e
      redirect_to edit_admin_product_path(@product), alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      @product.product_colorways.find(params[:id]).destroy!
      redirect_to edit_admin_product_path(@product), notice: "Colorway removed."
    end

    private

    def set_product
      @product = current_store.products.find_by!(slug: params[:product_id])
    end

    def recolor_source!
      unless source_attachment.content_type.to_s.start_with?("image/")
        raise Recolor::Error, "Choose a JPEG, PNG, or WebP photo."
      end
      raise Recolor::Error, "That image is too large to recolor." if source_attachment.byte_size > 15.megabytes

      Recolor::Client.recolor(
        image_bytes: source_attachment.download,
        filename: source_attachment.filename.to_s,
        content_type: source_attachment.content_type,
        hex: parsed_hex,
        prompt: parsed_prompt,
        points: parsed_points
      )
    end

    def source_attachment
      @source_attachment ||= @product.images.find(params[:attachment_id])
    end

    def parsed_hex
      @parsed_hex ||= Recolor.normalize_hex(params[:hex])
    end

    def parsed_name
      name = params[:name].to_s.strip.first(60)
      raise Recolor::Error, "Name this colorway." if name.blank?

      name
    end

    def parsed_prompt
      params[:prompt].to_s.strip.first(160)
    end

    def parsed_points
      raw = params[:points].presence || "[]"
      list = raw.is_a?(String) ? JSON.parse(raw) : Array(raw)
      raise Recolor::Error, "Could not read the click points." unless list.is_a?(Array)

      list.first(12).filter_map do |pair|
        next unless pair.is_a?(Array) && pair.size == 2

        x = Float(pair[0])
        y = Float(pair[1])
        next unless x.finite? && y.finite? && x.between?(0.0, 1.0) && y.between?(0.0, 1.0)

        [ x.round(4), y.round(4) ]
      end
    rescue JSON::ParserError, ArgumentError, TypeError
      raise Recolor::Error, "Could not read the click points."
    end

    def data_url(bytes)
      "data:image/png;base64,#{Base64.strict_encode64(bytes)}"
    end
  end
end
