class CreateShopifyPrivacyRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :shopify_privacy_requests do |t|
      t.references :store_connection, foreign_key: true
      t.string :event_key, null: false
      t.string :topic, null: false
      t.string :status, null: false, default: "pending"
      t.text :identifiers_ciphertext
      t.string :error_code
      t.datetime :processed_at
      t.timestamps
    end
    add_index :shopify_privacy_requests, :event_key, unique: true
    add_check_constraint :shopify_privacy_requests,
      "topic IN ('customers/data_request', 'customers/redact', 'shop/redact')", name: "shopify_privacy_request_topic"
    add_check_constraint :shopify_privacy_requests,
      "status IN ('pending', 'needs_review', 'completed')", name: "shopify_privacy_request_status"
  end
end
