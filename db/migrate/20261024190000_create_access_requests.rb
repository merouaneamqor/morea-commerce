class CreateAccessRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :access_requests do |t|
      t.string :store_name, null: false
      t.string :email, null: false
      t.string :phone
      t.string :locale, null: false, default: "fr"
      t.string :status, null: false, default: "pending"
      t.string :ip
      t.references :store, foreign_key: { on_delete: :nullify }
      t.references :reviewed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :reviewed_at
      t.timestamps
    end
    add_check_constraint :access_requests, "status IN ('pending', 'approved', 'rejected')", name: "access_request_status"
    add_index :access_requests, :email, unique: true, where: "status = 'pending'", name: "index_access_requests_one_pending_per_email"
    add_index :access_requests, [ :status, :created_at ]
    add_index :access_requests, [ :ip, :created_at ]
  end
end
