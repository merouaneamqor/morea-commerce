# frozen_string_literal: true

class AddGoogleAnalyticsIdToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :google_analytics_id, :string
  end
end
