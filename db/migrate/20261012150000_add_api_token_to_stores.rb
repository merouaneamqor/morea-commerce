# frozen_string_literal: true

class AddApiTokenToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :api_token_digest, :string
    add_column :stores, :api_token_last_four, :string
    add_index :stores, :api_token_digest, unique: true
  end
end
