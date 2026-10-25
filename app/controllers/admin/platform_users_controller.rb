# frozen_string_literal: true

module Admin
  # Platform administrators manage workspace admins and other platform admins.
  class PlatformUsersController < BaseController
    layout "admin_platform"
    before_action :require_super_admin!
    before_action :enter_platform_mode
    before_action :set_user, only: %i[edit update lifecycle]

    ROLES = %w[all super_admin workspace_admin].freeze

    def index
      @status = User::STATUSES.include?(params[:status]) ? params[:status] : "active"
      @role = ROLES.include?(params[:role]) ? params[:role] : "all"
      @counts = managed_users.group(:status).count
      scope = managed_users.with_status(@status).includes(:store).order(:email)
      scope = scope.where(super_admin: true) if @role == "super_admin"
      scope = scope.where(super_admin: false) if @role == "workspace_admin"
      @users = scope.limit(200)
    end

    def new
      @user = User.new(admin: true)
    end

    def create
      @user = User.new
      assign_attributes
      if @user.password.blank?
        @user.errors.add(:password, :blank)
        return render :new, status: :unprocessable_entity
      end

      if @user.save
        redirect_to admin_platform_users_path, notice: t("platform_users.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      saved = User.transaction do
        # Use the same lock order as lifecycle changes so concurrent demotions
        # and suspensions cannot both remove the remaining platform admins.
        User.super_admins.active.order(:id).lock.pluck(:id)
        @user.lock!
        assign_attributes
        if (reason = demotion_denied_reason)
          @user.errors.add(:base, t("platform_users.denied.#{reason}"))
          false
        else
          @user.save
        end
      end

      if saved
        redirect_to admin_platform_users_path, notice: t("platform_users.saved")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def lifecycle
      action = params[:lifecycle].to_s
      Platform::UserLifecycle.new(user: @user, actor: current_user).call(action)
      redirect_to admin_platform_users_path(status: params[:return_status].presence), notice: t("platform_users.done.#{action}", email: @user.email)
    rescue Platform::UserLifecycle::Denied => e
      redirect_to admin_platform_users_path(status: params[:return_status].presence), alert: t("platform_users.denied.#{e.reason}")
    end

    private

    # Workspace admins plus platform admins; staff without admin access are
    # managed by their own workspace.
    def managed_users
      User.where("admin = TRUE OR super_admin = TRUE")
    end

    def set_user
      @user = managed_users.find(params[:id])
    end

    def enter_platform_mode
      session[:admin_mode] = "platform"
    end

    def assign_attributes
      attrs = params.require(:user).permit(:email, :name, :password, :password_confirmation, :store_id, :role)
      role = attrs.delete(:role)
      store_id = attrs.delete(:store_id)
      attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?
      @user.assign_attributes(attrs)
      @user.admin = true
      @user.super_admin = role == "super_admin"
      # Workspace must come from the Store table, never a free-form value.
      @user.store = store_id.present? ? Store.find(store_id) : nil
    end

    def demotion_denied_reason
      return unless @user.super_admin_was && !@user.super_admin?
      return :self if @user.id == current_user.id

      :last_super_admin if @user.active? && User.super_admins.active.where.not(id: @user.id).none?
    end
  end
end
