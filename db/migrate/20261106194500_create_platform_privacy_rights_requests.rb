# frozen_string_literal: true

class CreatePlatformPrivacyRightsRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :platform_privacy_rights_requests do |t|
      t.string :request_type, null: false
      t.string :status, null: false, default: "open"
      t.string :requester_name, null: false
      t.string :requester_contact, null: false
      t.text :details
      t.string :shop_domain
      t.datetime :resolved_at
      t.timestamps
    end

    add_index :platform_privacy_rights_requests, :status
    add_index :platform_privacy_rights_requests, :created_at
    add_check_constraint :platform_privacy_rights_requests,
      "request_type IN ('access', 'rectify', 'object', 'delete', 'unsubscribe')",
      name: "platform_privacy_rights_requests_type"
    add_check_constraint :platform_privacy_rights_requests,
      "status IN ('open', 'in_progress', 'resolved', 'rejected')",
      name: "platform_privacy_rights_requests_status"
  end
end
