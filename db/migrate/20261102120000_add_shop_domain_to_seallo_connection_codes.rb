class AddShopDomainToSealloConnectionCodes < ActiveRecord::Migration[8.1]
  def change
    add_column :seallo_connection_codes, :shop_domain, :string
    add_check_constraint :seallo_connection_codes, "shop_domain IS NULL OR char_length(shop_domain) <= 253", name: "seallo_connection_code_shop_domain_length"
  end
end
