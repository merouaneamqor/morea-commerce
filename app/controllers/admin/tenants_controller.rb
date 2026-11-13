# frozen_string_literal: true

module Admin
  # Provision merchant workspaces, with an optional public storefront.
  class TenantsController < BaseController
    layout "admin_platform"
    before_action :require_super_admin!
    before_action :enter_platform_mode, only: %i[index new create show edit update exit_workspace]
    before_action :set_store, only: %i[show edit update enter reset exit_workspace]

    def index
      redirect_to admin_platform_path
    end

    def show
    end

    def new
      @access_request = AccessRequest.pending.find_by(id: params[:access_request_id])
      @store = Store.new(
        currency: "MAD",
        billing_interval: "monthly",
        billing_status: "trial",
        billing_amount_cents: 0
      )
      return unless @access_request

      @store.assign_attributes(name: @access_request.store_name, slug: @access_request.store_name.parameterize,
        email: @access_request.email, phone: @access_request.phone,
        storefront_enabled: @access_request.storefront_enabled)
    end

    def create
      @store = Store.new(store_params)
      @access_request = AccessRequest.find(params[:access_request_id]) if params[:access_request_id].present?
      password = params.require(:admin).permit(:password)[:password].to_s
      email = params.require(:admin).permit(:email)[:email].to_s.strip.downcase

      if password.blank? || email.blank?
        @store.errors.add(:base, "First admin email and password are required.")
        return render :new, status: :unprocessable_entity
      end

      ActiveRecord::Base.transaction do
        if @access_request
          @access_request.lock!
          unless @access_request.pending?
            return redirect_to admin_access_requests_path, alert: t("platform_admin.request_already_reviewed")
          end
        end
        @store.save!
        @store.users.create!(
          email: email,
          name: "#{@store.name} Admin",
          password: password,
          password_confirmation: password,
          admin: true
        )
        @store.install_online_store_defaults! if @store.storefront_enabled?
        @access_request&.approve!(store: @store, reviewer: current_user)
      end

      redirect_to admin_tenant_path(@store), notice: t("platform_admin.workspace_created", name: @store.name, origin: "#{@store.origin}/admin")
    rescue ActiveRecord::RecordInvalid
      @access_request = AccessRequest.pending.find_by(id: params[:access_request_id])
      render :new, status: :unprocessable_entity
    end

    def edit
    end

    def update
      if update_workspace
        redirect_to admin_tenant_path(@store), notice: "Billing updated for #{@store.name}."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Wipes the workspace's data and settings back to a freshly provisioned state.
    def reset
      Platform::StoreReset.new(store: @store, actor: current_user, ip: request.remote_ip).call(confirmation: params[:confirmation])
      redirect_to admin_tenant_path(@store), notice: t("platform_admin.reset.done", name: @store.name), status: :see_other
    rescue Platform::StoreReset::Denied => e
      redirect_to edit_admin_tenant_path(@store), alert: t("platform_admin.reset.denied.#{e.reason}"), status: :see_other
    end

    # Open the workspace as one of its members. The platform account stays in the
    # session so the super admin can return without knowing that member's password.
    # Super admins can also enter a store directly without impersonating a user.
    def enter
      actor = current_user

      if params.key?(:user_id)
        # Impersonate a specific user
        user = @store.users.find_by(id: params[:user_id])
        unless user&.impersonatable_by_super_admin?
          return redirect_to admin_platform_path(anchor: "workspaces"), alert: t("platform_admin.impersonate.invalid")
        end

        session[:impersonator_id] = actor.id
        session[:impersonator_session_version] = actor.session_version
        session[:user_id] = user.id
        session[:session_version] = user.session_version
        session[:admin_mode] = "store"
        session[:admin_store_id] = @store.id
        session[:platform_workspace_id] = @store.id
        Platform::AdminAudit.record(
          action: "workspace.impersonate",
          actor: actor,
          store: @store,
          subject: user,
          ip: request.remote_ip,
          slug: @store.slug
        )
        redirect_to(user.confirmation_agent? ? home_admin_confirmations_path : admin_root_path)
      else
        # Direct access as super admin (no impersonation)
        session[:admin_mode] = "store"
        session[:admin_store_id] = @store.id
        session[:platform_workspace_id] = @store.id
        Platform::AdminAudit.record(
          action: "workspace.enter",
          actor: actor,
          store: @store,
          subject: @store,
          ip: request.remote_ip,
          slug: @store.slug
        )
        redirect_to admin_root_path
      end
    end

    # Leave merchant admin while keeping the platform workspace bookmark.
    def exit_workspace
      workspace_id = session[:platform_workspace_id].presence || @store.id
      session[:admin_mode] = "platform"
      session.delete(:admin_store_id)
      redirect_to admin_tenant_path(workspace_id)
    end

    private

    def enter_platform_mode
      session[:admin_mode] = "platform"
    end

    def set_store
      @store = Store.find(params[:id])
    end

    def store_params
      params.require(:store).permit(
        :name, :slug, :email, :phone, :currency, :storefront_enabled,
        :billing_interval, :billing_status, :billing_amount_dh, :billing_period_ends_on
      )
    end

    def billing_params
      params.require(:store).permit(
        :billing_interval, :billing_status, :billing_amount_dh, :billing_period_ends_on, :storefront_enabled
      )
    end

    def update_workspace
      @store.with_lock do
        was_enabled = @store.storefront_enabled?
        @store.update!(billing_params)
        @store.install_online_store_defaults! if !was_enabled && @store.storefront_enabled?
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end
  end
end
