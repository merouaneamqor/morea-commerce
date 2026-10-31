# frozen_string_literal: true

class CreatePlatformOauthGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :platform_oauth_codes do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :code_digest, null: false
      t.string :client_id, null: false
      t.string :redirect_uri, null: false
      t.string :code_challenge, null: false
      t.string :resource, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :platform_oauth_codes, :code_digest, unique: true

    create_table :platform_oauth_tokens do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :token_digest, null: false
      t.string :refresh_digest, null: false
      t.string :client_id, null: false
      t.string :resource, null: false
      t.datetime :expires_at, null: false
      t.datetime :refresh_expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :platform_oauth_tokens, :token_digest, unique: true
    add_index :platform_oauth_tokens, :refresh_digest, unique: true
  end
end
