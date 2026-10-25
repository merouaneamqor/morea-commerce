class CreateAdvertising < ActiveRecord::Migration[8.0]
  def change
    create_table :advertising_accounts do |t|
      t.references :store, null: false, foreign_key: true
      t.string :name, null: false
      t.string :provider, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    create_table :advertising_campaigns do |t|
      t.references :advertising_account, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    create_table :advertising_performances do |t|
      t.references :advertising_campaign, null: false, foreign_key: true, index: false
      t.date :date, null: false
      %i[spend_cents delivered_revenue_cents fulfillment_cost_cents confirmed_orders delivered_orders clicks impressions].each do |field|
        t.bigint field, null: false, default: 0
      end
      t.timestamps
    end
    add_index :advertising_performances, [:advertising_campaign_id, :date], unique: true, name: 'index_advertising_performance_day'
    %i[spend_cents delivered_revenue_cents fulfillment_cost_cents confirmed_orders delivered_orders clicks impressions].each do |field|
      add_check_constraint :advertising_performances, "#{field} >= 0", name: "advertising_#{field}_nonnegative"
    end
  end
end
