# frozen_string_literal: true

class AddOrderDeskFields < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :archived_at, :datetime
    add_column :orders, :tags, :string

    create_table :order_events do |t|
      t.references :order, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :kind, null: false
      t.text :body
      t.timestamps
    end

    add_index :orders, :archived_at
  end
end
