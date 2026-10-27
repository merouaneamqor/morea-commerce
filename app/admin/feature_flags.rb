# frozen_string_literal: true

ActiveAdmin.register_page "Feature Flags", namespace: :superadmin do
  menu priority: 1, label: "Feature flags"

  content title: "Feature flags" do
    panel "Storefront theme editor" do
      para "Enable theme installation, preview, editing and publishing for selected workspaces. The flag is disabled by default."

      table_for Store.order(:name) do
        column("Workspace") do |store|
          div do
            strong store.name
            div store.slug, class: "small"
          end
        end
        column("Storefront") { |store| status_tag(store.storefront_enabled? ? "Published" : "Unpublished") }
        column("Theme editor") { |store| status_tag(store.storefront_theme_editor_enabled? ? "Enabled" : "Disabled") }
        column do |store|
          enabled = !store.storefront_theme_editor_enabled?
          text_node helpers.button_to(
            enabled ? "Enable" : "Disable",
            superadmin_feature_flags_update_path,
            method: :patch,
            params: { store_id: store.id, enabled: enabled },
            class: "button"
          )
        end
      end
    end
  end

  page_action :update, method: :patch do
    store = Store.find(params.require(:store_id))
    enabled = ActiveModel::Type::Boolean.new.cast(params.require(:enabled))
    store.update!(storefront_theme_editor_enabled: enabled)

    redirect_to superadmin_feature_flags_path, notice: "Feature flags updated for #{store.name}."
  end
end
