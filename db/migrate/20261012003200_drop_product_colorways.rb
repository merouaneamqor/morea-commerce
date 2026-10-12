# frozen_string_literal: true

class DropProductColorways < ActiveRecord::Migration[8.1]
  def up
    if table_exists?(:product_colorways)
      attachments = ActiveStorage::Attachment.where(record_type: "ProductColorway")
      blob_ids = attachments.pluck(:blob_id)
      attachments.delete_all
      ActiveStorage::Blob.where(id: blob_ids).find_each(&:purge)
      drop_table :product_colorways
    end

    execute "DELETE FROM schema_migrations WHERE version = '20261011120000'"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
