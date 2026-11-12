# frozen_string_literal: true

# Each person can switch the dashboard's revenue milestones bar on or off (on by default).
class AddShowMilestonesToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :show_milestones, :boolean, default: true, null: false
  end
end
