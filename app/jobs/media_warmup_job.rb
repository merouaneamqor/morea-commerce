# frozen_string_literal: true

require "net/http"

# Cloudinary answers 423 while it runs a slow transformation (background removal)
# for the first time; request it once in the background so shoppers never see that.
class MediaWarmupJob < ApplicationJob
  queue_as :default

  class Pending < StandardError; end
  retry_on Pending, wait: 10.seconds, attempts: 8

  def perform(blob_id, store_id = nil)
    blob = ActiveStorage::Blob.find_by(id: blob_id)
    return unless blob && MediaUrl.cloudinary?(blob)

    store = Store.find_by(id: store_id) if store_id
    url = MediaUrl.sized(blob.url(transformation: MediaUrl.transformation(MediaUrl.edits(blob), store: store)), width: 960)
    response = Net::HTTP.get_response(URI(url))
    raise Pending, "#{response.code} for blob #{blob_id}" if response.code == "423"
  end
end
