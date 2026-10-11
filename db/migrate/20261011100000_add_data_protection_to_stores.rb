# frozen_string_literal: true

class AddDataProtectionToStores < ActiveRecord::Migration[8.1]
  def up
    add_column :stores, :legal_entity_name, :string
    add_column :stores, :cndp_authorization, :string
    add_column :stores, :privacy_rights_contact, :string

    Store.find_each { |store| DataProtection::Bootstrap.install_for_store!(store) }
  end

  def down
    remove_column :stores, :privacy_rights_contact
    remove_column :stores, :cndp_authorization
    remove_column :stores, :legal_entity_name
  end
end
