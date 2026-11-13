class CreatePushSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :push_subscriptions do |t|
      t.references :store, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.text :endpoint, null: false
      t.string :p256dh, null: false
      t.string :auth, null: false
      t.timestamps
    end
    # One row per browser: a device re-subscribing moves to its current user.
    add_index :push_subscriptions, :endpoint, unique: true
    add_check_constraint :push_subscriptions, "endpoint LIKE 'https://%'", name: "push_subscription_https_endpoint"
  end
end
