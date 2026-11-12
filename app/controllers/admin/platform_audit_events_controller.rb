# frozen_string_literal: true

module Admin
  # Browse privileged platform audit events. Metadata display is limited to
  # known non-secret keys from Platform::AdminAudit.
  class PlatformAuditEventsController < BaseController
    layout "admin_platform"
    before_action :require_super_admin!
    before_action :enter_platform_mode
    before_action :set_event, only: :show

    LIST_LIMIT = 100

    def index
      scope = AuditEvent.where(acting_as_platform: true).includes(:store, :actor_user).order(created_at: :desc, id: :desc)
      if params[:action_name].present?
        scope = scope.where("action ILIKE ?", "%#{AuditEvent.sanitize_sql_like(params[:action_name].to_s.strip)}%")
      end
      if params[:store_id].present?
        scope = scope.where(store_id: params[:store_id].to_i)
      end
      if params[:actor].present?
        actor_q = "%#{AuditEvent.sanitize_sql_like(params[:actor].to_s.strip)}%"
        scope = scope.left_joins(:actor_user).where(
          "audit_events.actor_label ILIKE :q OR users.email ILIKE :q",
          q: actor_q
        )
      end
      @events = scope.limit(LIST_LIMIT)
      @action_name = params[:action_name].to_s
      @store_id = params[:store_id].to_s
      @actor = params[:actor].to_s
    end

    def show
      @safe_metadata = safe_metadata(@event.metadata)
    end

    private

    def enter_platform_mode
      session[:admin_mode] = "platform"
    end

    def set_event
      @event = AuditEvent.where(acting_as_platform: true).find(params[:id])
    end

    def safe_metadata(raw)
      values = raw.is_a?(Hash) ? raw : {}
      allowed = Platform::AdminAudit::METADATA_KEYS.map(&:to_s)
      values.stringify_keys.slice(*allowed)
    end
  end
end
