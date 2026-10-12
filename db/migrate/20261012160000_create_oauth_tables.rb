# frozen_string_literal: true

class CreateOauthTables < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_clients do |t|
      t.string :client_id, null: false
      t.string :client_name
      t.string :redirect_uris, array: true, default: [], null: false
      t.timestamps
    end
    add_index :oauth_clients, :client_id, unique: true

    create_table :oauth_access_tokens do |t|
      t.references :store, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :refresh_digest, null: false
      t.string :client_id, null: false
      t.datetime :expires_at, null: false
      t.datetime :refresh_expires_at, null: false
      t.timestamps
    end
    add_index :oauth_access_tokens, :token_digest, unique: true
    add_index :oauth_access_tokens, :refresh_digest, unique: true
  end
end
