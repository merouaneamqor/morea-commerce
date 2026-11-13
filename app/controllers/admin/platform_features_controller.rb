# frozen_string_literal: true

module Admin
  # Platform shell for home-page gates and per-workspace theme editor flags.
  # ActiveAdmin /superadmin/feature_flags remains available and unchanged.
  class PlatformFeaturesController < BaseController
    layout "admin_platform"
    before_action :require_super_admin!
    before_action :enter_platform_mode

    HISTORY_LIMIT = 40

    def show
      @setting = PlatformSetting.current
      @stores = Store.order(:name)
      @flag_events = AuditEvent.where("action LIKE ?", "feature_flag.%")
        .includes(:actor_user, :store)
        .order(created_at: :desc)
        .limit(HISTORY_LIMIT)
    end

    def update_home
      flag = params[:flag].to_s
      unless PlatformSetting::HOME_FLAGS.include?(flag)
        return redirect_to admin_platform_features_path, alert: t("platform_admin.features.unknown_flag")
      end

      enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
      setting = PlatformSetting.current
      setting.update!(flag => enabled)

      Platform::AdminAudit.record(
        action: "feature_flag.home",
        actor: current_user,
        subject: setting,
        source: "ui",
        ip: request.remote_ip,
        flag: flag,
        enabled: enabled
      )

      redirect_to admin_platform_features_path,
        notice: t(
          "platform_admin.features.updated_home",
          flag: t("platform_admin.features.flags.#{flag}"),
          status: enabled_label(enabled),
          state: t("platform_admin.features.home_states.#{setting.reload.home_page}")
        )
    end

    def update_store
      store = Store.find_by(id: params[:store_id])
      return redirect_to admin_platform_features_path, alert: t("platform_admin.features.store_missing") unless store

      enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
      store.update!(storefront_theme_editor_enabled: enabled)

      Platform::AdminAudit.record(
        action: "feature_flag.theme_editor",
        actor: current_user,
        store: store,
        subject: store,
        source: "ui",
        ip: request.remote_ip,
        flag: "storefront_theme_editor_enabled",
        enabled: enabled
      )

      redirect_to admin_platform_features_path,
        notice: t(
          "platform_admin.features.updated_store",
          name: store.name,
          status: enabled_label(enabled)
        )
    end

    private

    def enter_platform_mode
      session[:admin_mode] = "platform"
    end

    def enabled_label(enabled)
      enabled ? t("platform_admin.features.enabled") : t("platform_admin.features.disabled")
    end
  end
end
