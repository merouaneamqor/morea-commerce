class CreateCommerceSchema < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :name
      t.boolean :admin, default: true, null: false

      t.timestamps
    end
    add_index :users, :email, unique: true

    create_table :stores do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :tagline
      t.text :about
      t.string :phone
      t.string :email
      t.string :currency, default: "DH", null: false
      t.string :cod_label, default: "Cash on delivery"
      t.text :cod_note
      t.bigint :featured_product_id
      t.bigint :featured_collection_id

      t.timestamps
    end
    add_index :stores, :slug, unique: true

    create_table :collections do |t|
      t.references :store, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.string :subtitle
      t.text :description
      t.boolean :published, default: true, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end
    add_index :collections, [:store_id, :slug], unique: true

    create_table :products do |t|
      t.references :store, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.string :status, default: "draft", null: false
      t.integer :price_cents, null: false
      t.integer :compare_at_cents
      t.string :currency, default: "DH", null: false
      t.text :short_description
      t.text :story
      t.text :material
      t.text :dimensions
      t.string :origin
      t.text :care
      t.string :sku
      t.integer :stock, default: 0, null: false
      t.boolean :track_inventory, default: true, null: false
      t.boolean :featured, default: false, null: false
      t.integer :position, default: 0, null: false
      t.string :seo_title
      t.string :seo_description
      t.string :image_url
      t.string :detail_image_url

      t.timestamps
    end
    add_index :products, [:store_id, :slug], unique: true
    add_index :products, :status
    add_index :products, :featured

    create_table :product_variants do |t|
      t.references :product, null: false, foreign_key: true
      t.string :name, null: false
      t.string :sku
      t.string :option1_name
      t.string :option1_value
      t.string :option2_name
      t.string :option2_value
      t.integer :price_cents
      t.integer :stock, default: 0, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    create_table :collection_products do |t|
      t.references :collection, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :position, default: 0, null: false

      t.timestamps
    end
    add_index :collection_products, [:collection_id, :product_id], unique: true

    create_table :customers do |t|
      t.references :store, null: false, foreign_key: true
      t.string :name, null: false
      t.string :phone, null: false
      t.string :email
      t.string :city
      t.integer :orders_count, default: 0, null: false

      t.timestamps
    end
    add_index :customers, [:store_id, :phone], unique: true

    create_table :addresses do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :city, null: false
      t.string :line1, null: false
      t.string :line2
      t.boolean :default, default: true, null: false

      t.timestamps
    end

    create_table :carts do |t|
      t.references :store, null: false, foreign_key: true
      t.string :token, null: false

      t.timestamps
    end
    add_index :carts, :token, unique: true

    create_table :cart_items do |t|
      t.references :cart, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.references :product_variant, foreign_key: true
      t.integer :quantity, default: 1, null: false
      t.integer :unit_price_cents, null: false

      t.timestamps
    end

    create_table :orders do |t|
      t.references :store, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.string :number, null: false
      t.string :status, default: "new", null: false
      t.string :payment_method, default: "cod", null: false
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :shipping_cents, null: false, default: 0
      t.integer :total_cents, null: false, default: 0
      t.string :currency, default: "DH", null: false
      t.string :customer_name, null: false
      t.string :customer_phone, null: false
      t.string :customer_city, null: false
      t.string :customer_address, null: false
      t.text :notes
      t.datetime :confirmed_at
      t.datetime :shipped_at
      t.datetime :delivered_at
      t.datetime :cancelled_at
      t.string :cancel_reason

      t.timestamps
    end
    add_index :orders, :number, unique: true
    add_index :orders, :status
    add_index :orders, :customer_phone

    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.references :product_variant, foreign_key: true
      t.string :product_name, null: false
      t.string :variant_name
      t.integer :quantity, null: false
      t.integer :unit_price_cents, null: false
      t.integer :total_cents, null: false

      t.timestamps
    end

    create_table :inventory_movements do |t|
      t.references :product, null: false, foreign_key: true
      t.references :product_variant, foreign_key: true
      t.references :order, foreign_key: true
      t.integer :quantity, null: false
      t.string :reason, null: false
      t.string :note

      t.timestamps
    end

    create_table :discounts do |t|
      t.references :store, null: false, foreign_key: true
      t.string :code, null: false
      t.string :discount_type, default: "percent", null: false
      t.integer :value, null: false
      t.boolean :active, default: true, null: false
      t.datetime :starts_at
      t.datetime :ends_at

      t.timestamps
    end
    add_index :discounts, [:store_id, :code], unique: true
  end
end
