# frozen_string_literal: true

class CreateAgentAutonomy < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :agent_profile, :jsonb, null: false, default: {}

    create_table :agent_changesets do |t|
      t.references :store, null: false, foreign_key: true
      t.string :token, null: false
      t.string :status, null: false, default: "previewed"
      t.string :summary
      t.jsonb :operations, null: false, default: []
      t.jsonb :preview, null: false, default: {}
      t.jsonb :snapshots, null: false, default: []
      t.jsonb :results, null: false, default: {}
      t.jsonb :verification, null: false, default: {}
      t.integer :max_level, null: false, default: 1
      t.datetime :applied_at
      t.datetime :verified_at
      t.datetime :rolled_back_at
      t.timestamps
    end

    add_index :agent_changesets, [ :store_id, :token ], unique: true
    add_index :agent_changesets, :status
  end
end
