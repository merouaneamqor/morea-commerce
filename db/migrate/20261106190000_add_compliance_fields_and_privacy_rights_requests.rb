# frozen_string_literal: true

class AddComplianceFieldsAndPrivacyRightsRequests < ActiveRecord::Migration[8.1]
  def up
    add_column :stores, :legal_registration_number, :string
    add_column :stores, :legal_address, :string
    add_column :stores, :minimum_purchase_age, :integer, null: false, default: 16

    create_table :privacy_rights_requests do |t|
      t.references :store, null: false, foreign_key: true
      t.string :request_type, null: false
      t.string :status, null: false, default: "open"
      t.string :requester_name, null: false
      t.string :requester_contact, null: false
      t.text :details
      t.string :order_number
      t.datetime :resolved_at
      t.timestamps
    end

    add_index :privacy_rights_requests, [ :store_id, :status ]
    add_index :privacy_rights_requests, [ :store_id, :created_at ]
    add_check_constraint :privacy_rights_requests,
      "request_type IN ('access', 'rectify', 'object', 'delete', 'unsubscribe')",
      name: "privacy_rights_requests_type"
    add_check_constraint :privacy_rights_requests,
      "status IN ('open', 'in_progress', 'resolved', 'rejected')",
      name: "privacy_rights_requests_status"
    add_check_constraint :stores,
      "minimum_purchase_age >= 13 AND minimum_purchase_age <= 21",
      name: "stores_minimum_purchase_age_range"

    say_with_time "install compliance pages for existing storefronts" do
      Store.find_each { |store| DataProtection::Bootstrap.install_for_store!(store) }
    end
  end

  def down
    drop_table :privacy_rights_requests
    remove_column :stores, :minimum_purchase_age
    remove_column :stores, :legal_address
    remove_column :stores, :legal_registration_number
  end
end
