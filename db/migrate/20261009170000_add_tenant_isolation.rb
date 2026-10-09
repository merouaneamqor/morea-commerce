# frozen_string_literal: true

class AddTenantIsolation < ActiveRecord::Migration[8.1]
  def up
    add_reference :users, :store, foreign_key: true

    add_column :stores, :sendit_public_key, :text
    add_column :stores, :sendit_secret_key, :text
    add_column :stores, :sendit_webhook_secret, :text
    add_column :stores, :discord_orders_webhook_url, :text

    morea_id = select_value("SELECT id FROM stores WHERE slug = 'morea' ORDER BY id LIMIT 1")
    morea_id ||= select_value("SELECT id FROM stores ORDER BY id LIMIT 1")

    if morea_id
      execute "UPDATE users SET store_id = #{morea_id.to_i} WHERE store_id IS NULL"

      attrs = {
        sendit_public_key: ENV["SENDIT_PUBLIC_KEY"].presence,
        sendit_secret_key: ENV["SENDIT_SECRET_KEY"].presence,
        sendit_webhook_secret: ENV["SENDIT_WEBHOOK_SECRET"].presence,
        discord_orders_webhook_url: ENV["DISCORD_ORDERS_WEBHOOK_URL"].presence
      }.compact

      if attrs.any?
        sets = attrs.map { |column, value| "#{column} = COALESCE(#{column}, #{connection.quote(value)})" }.join(", ")
        execute "UPDATE stores SET #{sets} WHERE id = #{morea_id.to_i}"
      end
    else
      execute "DELETE FROM users WHERE store_id IS NULL"
    end

    change_column_null :users, :store_id, false

    remove_index :users, :email
    add_index :users, [ :store_id, :email ], unique: true

    remove_index :orders, :number
    add_index :orders, [ :store_id, :number ], unique: true

    remove_index :carts, :token
    add_index :carts, [ :store_id, :token ], unique: true

    remove_index :orders, :sendit_code
    add_index :orders, [ :store_id, :sendit_code ], unique: true, where: "sendit_code IS NOT NULL"
  end

  def down
    remove_index :orders, name: "index_orders_on_store_id_and_sendit_code"
    add_index :orders, :sendit_code, unique: true

    remove_index :carts, [ :store_id, :token ]
    add_index :carts, :token, unique: true

    remove_index :orders, [ :store_id, :number ]
    add_index :orders, :number, unique: true

    remove_index :users, [ :store_id, :email ]
    add_index :users, :email, unique: true

    remove_reference :users, :store, foreign_key: true

    remove_column :stores, :sendit_public_key
    remove_column :stores, :sendit_secret_key
    remove_column :stores, :sendit_webhook_secret
    remove_column :stores, :discord_orders_webhook_url
  end
end
