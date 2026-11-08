# frozen_string_literal: true

ActiveAdmin.register_page "Feature Flags", namespace: :superadmin do
  menu priority: 1, label: "Feature flags"

  content title: "Feature flags" do
    setting = PlatformSetting.current

    panel "Public home page" do
      para "Choose what visitors see on the platform home page. Store admin, signup, and each storefront stay available. When both flags are on, visitors see Under maintenance."
      para "Visitors currently see: #{setting.home_page_label}."

      table_for [
        { label: "Under maintenance", flag: "home_maintenance", enabled: setting.home_maintenance? },
        { label: "Coming soon", flag: "home_coming_soon", enabled: setting.home_coming_soon? }
      ] do
        column("Page") { |row| row[:label] }
        column("Status") { |row| status_tag(row[:enabled] ? "Enabled" : "Disabled") }
        column do |row|
          text_node helpers.button_to(
            row[:enabled] ? "Disable" : "Enable",
            superadmin_feature_flags_update_home_path,
            method: :patch,
            params: { flag: row[:flag], enabled: !row[:enabled] },
            class: "button"
          )
        end
      end
    end

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

  page_action :update_home, method: :patch do
    flag = params[:flag].to_s
    if PlatformSetting::HOME_FLAGS.include?(flag)
      PlatformSetting.current.update!(flag => ActiveModel::Type::Boolean.new.cast(params[:enabled]))
      redirect_to superadmin_feature_flags_path, notice: "Public home page updated."
    else
      redirect_to superadmin_feature_flags_path, alert: "Unknown home page flag."
    end
  end

  page_action :update, method: :patch do
    store = Store.find(params.require(:store_id))
    enabled = ActiveModel::Type::Boolean.new.cast(params.require(:enabled))
    store.update!(storefront_theme_editor_enabled: enabled)

    redirect_to superadmin_feature_flags_path, notice: "Feature flags updated for #{store.name}."
  end
end
