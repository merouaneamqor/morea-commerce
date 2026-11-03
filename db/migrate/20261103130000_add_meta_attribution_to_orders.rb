# Which Meta ad brought an order, taken from the UTM parameters the merchant puts on every ad:
#   utm_source=facebook&utm_campaign={{campaign.id}}&utm_term={{adset.id}}&utm_content={{ad.id}}
# NULL means "not attributed": orders are never matched to an ad by guessing.
class AddMetaAttributionToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :meta_campaign_id, :string, limit: 25
    add_column :orders, :meta_adset_id, :string, limit: 25
    add_column :orders, :meta_ad_id, :string, limit: 25

    add_check_constraint :orders, "meta_campaign_id IS NULL OR meta_campaign_id ~ '^[0-9]{5,25}$'", name: "orders_meta_campaign_id_numeric"
    add_check_constraint :orders, "meta_adset_id IS NULL OR meta_adset_id ~ '^[0-9]{5,25}$'", name: "orders_meta_adset_id_numeric"
    add_check_constraint :orders, "meta_ad_id IS NULL OR meta_ad_id ~ '^[0-9]{5,25}$'", name: "orders_meta_ad_id_numeric"
    # An ad set or ad can only be known together with its campaign.
    add_check_constraint :orders, "(meta_adset_id IS NULL AND meta_ad_id IS NULL) OR meta_campaign_id IS NOT NULL", name: "orders_meta_ids_need_campaign"

    add_index :orders, %i[store_id meta_campaign_id created_at], where: "meta_campaign_id IS NOT NULL", name: "index_orders_on_meta_campaign"
    add_index :orders, %i[store_id meta_adset_id created_at], where: "meta_adset_id IS NOT NULL", name: "index_orders_on_meta_adset"
    add_index :orders, %i[store_id meta_ad_id created_at], where: "meta_ad_id IS NOT NULL", name: "index_orders_on_meta_ad"
  end
end
