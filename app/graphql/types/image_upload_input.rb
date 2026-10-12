# frozen_string_literal: true

module Types
  class ImageUploadInput < BaseInput
    argument :base64, String, required: false, description: "Raw or data-URL base64 image bytes"
    argument :url, String, required: false, description: "Public http(s) image URL"
    argument :filename, String, required: false
    argument :content_type, String, required: false, description: "image/jpeg, image/png, image/webp, or image/gif"
  end
end
