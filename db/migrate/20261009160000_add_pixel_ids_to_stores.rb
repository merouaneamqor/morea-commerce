# frozen_string_literal: true

class AddPixelIdsToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :meta_pixel_id, :string
    add_column :stores, :tiktok_pixel_id, :string
  end
end
