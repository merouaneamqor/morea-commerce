class CreateWoocommerceConnectionCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :woocommerce_connection_codes do |t|
      t.references :store, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :digest, null: false
      t.string :site_domain, null: false
      t.string :code_challenge, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :woocommerce_connection_codes, :digest, unique: true
    add_check_constraint :woocommerce_connection_codes, "char_length(site_domain) <= 253", name: "woocommerce_connection_code_site_domain_length"
    add_check_constraint :woocommerce_connection_codes, "char_length(code_challenge) = 43", name: "woocommerce_connection_code_challenge_length"
  end
end
