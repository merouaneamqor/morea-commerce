# WhatsApp Business (Cloud API) accounts of a store, and the log of the messages sent through them (new-order messages and tests).
class CreateWhatsappAccountsAndMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :whatsapp_accounts do |t|
      t.references :store, null: false, foreign_key: true
      t.string :name, null: false
      t.string :display_phone
      t.string :phone_number_id, null: false
      t.string :business_account_id
      t.text :access_token_ciphertext, null: false
      t.string :api_version, null: false, default: "v21.0"
      t.boolean :read_receipts, null: false, default: true
      t.boolean :auto_send_new_orders, null: false, default: false
      t.text :new_order_message
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :whatsapp_accounts, %i[store_id phone_number_id], unique: true
    add_check_constraint :whatsapp_accounts, "new_order_message IS NULL OR char_length(new_order_message) <= 1000", name: "whatsapp_accounts_message_length"

    create_table :whatsapp_messages do |t|
      t.references :store, null: false, foreign_key: true
      t.references :whatsapp_account, null: false, foreign_key: { on_delete: :cascade }
      t.references :order, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false
      t.string :to_phone, null: false
      t.text :body, null: false
      t.string :status, null: false, default: "queued"
      t.string :wa_message_id
      t.text :error
      t.datetime :sent_at
      t.timestamps
    end
    add_check_constraint :whatsapp_messages, "kind IN ('new_order', 'test')", name: "whatsapp_messages_kind"
    add_check_constraint :whatsapp_messages, "status IN ('queued', 'sent', 'failed')", name: "whatsapp_messages_status"
    # One automatic message per order, whatever happens to the job.
    add_index :whatsapp_messages, %i[order_id kind], unique: true, where: "kind = 'new_order' AND order_id IS NOT NULL", name: "index_whatsapp_messages_one_new_order_message"
  end
end
