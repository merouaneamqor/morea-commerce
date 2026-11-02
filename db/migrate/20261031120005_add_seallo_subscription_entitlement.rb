class AddSealloSubscriptionEntitlement < ActiveRecord::Migration[8.1]
  def change
    add_column :store_connections, :shopify_entitled_until, :datetime
    add_column :store_connections, :shopify_plan_name, :string
    add_column :store_connections, :shopify_order_limit, :integer
    add_column :store_connections, :shopify_billing_period_start, :datetime
    add_column :store_connections, :shopify_billing_period_end, :datetime
    add_check_constraint :store_connections, "shopify_order_limit IS NULL OR shopify_order_limit > 0", name: "seallo_positive_order_limit"
    add_check_constraint :store_connections, "shopify_entitled_until IS NULL OR (shopify_app = 'seallo_connect' AND shopify_billing_period_start IS NOT NULL AND shopify_billing_period_end > shopify_billing_period_start)", name: "seallo_subscription_period"
  end
end
