# The address of the merchant's own site, shown (and clickable) to the confirmation agents in their menu.
class AddWebsiteUrlToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :website_url, :string
    add_check_constraint :stores, "website_url IS NULL OR char_length(website_url) <= 200", name: "stores_website_url_length"
  end
end
