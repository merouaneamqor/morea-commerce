# Sendit accounts get a secret webhook token (part of the URL pasted in Sendit) and the state of the city list refresh.
class AddSenditFieldsToDeliveryAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :delivery_accounts, :webhook_token, :string
    add_column :delivery_accounts, :cities_count, :integer
    add_column :delivery_accounts, :cities_synced_at, :datetime
    add_index :delivery_accounts, :webhook_token, unique: true, where: "webhook_token IS NOT NULL"
  end
end
