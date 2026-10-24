class CreateAuditEventsAndAdminSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events do |t|
      t.references :store, foreign_key: { on_delete: :nullify }
      t.references :actor_user, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :actor_label
      t.string :source, null: false
      t.boolean :acting_as_platform, null: false, default: false
      t.string :action, null: false
      t.string :subject_type
      t.bigint :subject_id
      t.jsonb :metadata, null: false, default: {}
      t.string :ip
      t.datetime :created_at, null: false
    end
    add_index :audit_events, [ :store_id, :created_at ]
    add_index :audit_events, [ :action, :created_at ]
    add_check_constraint :audit_events, "source IN ('ui', 'api', 'mcp', 'job', 'system')", name: "audit_event_source"

    create_table :admin_sessions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :store, foreign_key: { on_delete: :cascade }
      t.string :token_digest, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.string :ip
      t.string :user_agent
      t.timestamps
    end
    add_index :admin_sessions, :token_digest, unique: true
  end
end
