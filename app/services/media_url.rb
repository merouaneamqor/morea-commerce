# frozen_string_literal: true

# URLs for uploaded images. Cloudinary blobs get on-the-fly transformations:
# the admin's batch edits (crop, background removal, watermark) are stored in
# the blob metadata and applied at delivery, so originals are never altered.
# Disk blobs fall back to the plain Active Storage path.
module MediaUrl
  CROPS = {
    "portrait" => { aspect_ratio: "3:4", crop: "fill", gravity: "auto" },
    "square" => { aspect_ratio: "1:1", crop: "fill", gravity: "auto" }
  }.freeze

  EDITS = {
    "portrait" => "Crop 3:4",
    "square" => "Crop square",
    "remove_bg" => "Remove background",
    "watermark" => "Watermark"
  }.freeze

  # Store floor colour behind cut-outs, so JPEG fallbacks aren't black
  CUTOUT_BACKGROUND = "rgb:F7F5F2"

  module_function

  def for(attachment, store: nil)
    blob = attachment.blob
    return Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true) unless cloudinary?(blob)

    blob.url(transformation: transformation(edits(blob), store: store).presence || nil)
  end

  def cloudinary?(blob)
    blob.service_name == "cloudinary"
  end

  def edits(blob)
    Array(blob.metadata["edits"]) & EDITS.keys
  end

  # A crop replaces the previous crop, other edits add up; "clear" restores the original
  def apply!(blob, edit)
    current = edits(blob)
    updated =
      case edit
      when "clear" then []
      when *CROPS.keys then (current - CROPS.keys) + [ edit ]
      when *EDITS.keys then current | [ edit ]
      else return false
      end
    blob.update!(metadata: blob.metadata.merge("edits" => updated))
  end

  def transformation(edits, store: nil)
    steps = []
    crop = edits.find { |e| CROPS.key?(e) }
    steps << CROPS[crop] if crop
    steps.push({ effect: "background_removal" }, { background: CUTOUT_BACKGROUND }) if edits.include?("remove_bg")
    steps.concat(watermark(store)) if edits.include?("watermark")
    steps
  end

  def watermark(store)
    text = (store&.name.presence || "MOREA").upcase
    [
      # Work at a fixed width so the text keeps the same proportion after any crop
      # (relative overlay sizes are measured against the uncropped original)
      { width: 1600, crop: "scale" },
      { overlay: { font_family: "Arial", font_size: 96, font_weight: "bold", text: text }, color: "#FFFFFF", opacity: 70 },
      { flags: "layer_apply", gravity: "south_east", x: 64, y: 64 }
    ]
  end

  # Resize + modern format/quality for a Cloudinary delivery URL, after any edits
  def sized(url, width:)
    return url unless url.to_s.include?("res.cloudinary.com/") && url.include?("/image/upload/")

    url.sub(%r{/(v\d+/)}, "/c_limit,f_auto,q_auto,w_#{width}/\\1")
  end
end
