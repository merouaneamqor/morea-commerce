# frozen_string_literal: true

class CreatePlatformApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :platform_api_tokens do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :token_digest, null: false
      t.string :last_four, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :platform_api_tokens, :token_digest, unique: true
    add_index :platform_api_tokens, :user_id, unique: true, where: "revoked_at IS NULL", name: "index_platform_api_tokens_one_live_per_user"
  end
end
