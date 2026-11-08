# frozen_string_literal: true

class CreatePlatformSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :platform_settings do |t|
      t.boolean :singleton, null: false, default: true
      t.boolean :home_maintenance, null: false, default: false
      t.boolean :home_coming_soon, null: false, default: false
      t.timestamps
    end

    add_index :platform_settings, :singleton, unique: true
  end
end
