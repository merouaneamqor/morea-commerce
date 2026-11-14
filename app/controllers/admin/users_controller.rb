module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[edit update destroy pay permissions role status]

    def index
      @tab = %w[roles permissions].include?(params[:tab]) ? params[:tab] : "users"
      @query = params[:q].to_s.strip
      @all_users = current_store.users.order(:email)
      @users = @all_users
      if @query.present?
        like = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
        @users = @users.where("users.name ILIKE :like OR users.email ILIKE :like", like: like)
      end
      @users = @users.includes(:created_by)
      @permission_user = @all_users.reject(&:super_admin?).find { |user| user.id == params[:user_id].to_i }
      @activity = Team::Activity.new(store: current_store, users: @all_users.reject(&:super_admin?))
      @activity_rows = @activity.filtered(presence: params[:presence], role: params[:role], query: params[:aq])
      earnings = Team::AgentEarnings.new(store: current_store, range: Time.current.beginning_of_month..Time.current)
      @summaries = @users.to_h { |user| [ user.id, earnings.summary_for(user) ] }
    end

    def new
      @user = current_store.users.new(admin: true)
    end

    def create
      @user = current_store.users.new(user_params)
      @user.created_by = current_user
      if valid_staff_access? && @user.save
        redirect_to admin_users_path, notice: "Staff account created."
      else
        render :new, status: :unprocessable_entity
      end
    rescue ArgumentError => e
      @user = current_store.users.new(user_params_without_pay)
      @user.errors.add(:base, e.message)
      render :new, status: :unprocessable_entity
    end

    def edit
    end

    def update
      attrs = user_params
      attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?

      @user.assign_attributes(attrs)
      if valid_staff_access? && @user.save
        redirect_to admin_users_path, notice: "Staff account saved."
      elsif params[:inline].present?
        redirect_to admin_users_path, alert: @user.errors.full_messages.to_sentence
      else
        render :edit, status: :unprocessable_entity
      end
    rescue ArgumentError => e
      @user.assign_attributes(user_params_without_pay.except(:password, :password_confirmation))
      @user.errors.add(:base, e.message)
      render :edit, status: :unprocessable_entity
    end

    def destroy
      if @user == current_user
        redirect_to admin_users_path, alert: "You cannot delete your own account."
      elsif current_store.users.where(admin: true).where.not(id: @user.id).none?
        redirect_to admin_users_path, alert: "Keep at least one admin account."
      else
        @user.destroy!
        redirect_to admin_users_path, notice: "Staff account deleted."
      end
    end

    # Records one payment covering everything earned and not yet paid (paid in cash; the Facturation page of the agents also records a bank transfer and a proof).
    def pay
      Team::AgentPayout.new(store: current_store, agent: @user, paid_by: current_user).pay_all!(method: "cash")
      redirect_to admin_users_path, notice: t("admin.team.paid", name: @user.name.presence || @user.email)
    rescue Team::AgentPayout::Error => e
      redirect_to admin_users_path, alert: e.message == "Nothing to pay." ? t("admin.team.nothing_to_pay") : e.message
    end

    # Saves which areas of the store this person may open. It can only narrow what their role gives; the same list as the role's means "no custom list".
    # You cannot change your own, nor a platform super administrator's.
    def permissions
      back = admin_users_path(tab: "permissions", user_id: @user.id)
      return redirect_to(back, alert: t("admin.permissions.not_editable")) if @user == current_user || @user.super_admin?

      if params[:reset].present?
        @user.update!(custom_permissions: nil)
      else
        areas = Array(params[:areas]).map(&:to_s).reject(&:blank?) & @user.role_areas
        @user.update!(custom_permissions: areas.sort == @user.role_areas.sort ? nil : areas)
      end
      redirect_to back, notice: t("admin.permissions.saved", name: @user.name.presence || @user.email)
    rescue ActiveRecord::RecordInvalid => e
      redirect_to back, alert: e.message
    end

    # Gives the person the owner or the agent role (the owner and agent areas are different, so a custom permissions list is dropped). Not yourself, not a super
    # administrator, and never the last owner.
    def role
      return redirect_to(admin_users_path, alert: t("admin.permissions.not_editable")) if @user == current_user || @user.super_admin?

      attrs = case params[:role]
      when "owner" then { admin: true, confirmation_role: "supervisor", custom_permissions: nil }
      when "agent" then { admin: false, confirmation_role: "agent", custom_permissions: nil }
      end
      return redirect_to(admin_users_path, alert: t("admin.team_actions.unknown_role")) unless attrs
      return redirect_to(admin_users_path, alert: t("admin.team_actions.last_owner")) if !attrs[:admin] && @user.admin? && current_store.users.where(admin: true).where.not(id: @user.id).none?

      @user.update!(attrs.merge(session_version: @user.session_version + 1))
      redirect_to admin_users_path, notice: t("admin.team_actions.role_changed", name: @user.name.presence || @user.email)
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_users_path, alert: e.message
    end

    # Deactivate (they can no longer sign in, and are signed out) or reactivate. Not yourself, not a super administrator, never the last owner.
    def status
      return redirect_to(admin_users_path, alert: t("admin.permissions.not_editable")) if @user == current_user || @user.super_admin?

      if @user.active?
        return redirect_to(admin_users_path, alert: t("admin.team_actions.last_owner")) if @user.admin? && current_store.users.active.where(admin: true).where.not(id: @user.id).none?

        @user.update!(status: "suspended", status_changed_at: Time.current, session_version: @user.session_version + 1)
        redirect_to admin_users_path, notice: t("admin.team_actions.deactivated", name: @user.name.presence || @user.email)
      else
        @user.update!(status: "active", status_changed_at: Time.current)
        redirect_to admin_users_path, notice: t("admin.team_actions.reactivated", name: @user.name.presence || @user.email)
      end
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_users_path, alert: e.message
    end

    private

    def set_user
      @user = current_store.users.find(params[:id])
    end

    # A supervisor needs explicit admin access; never silently save an unusable
    # account or grant permissions when the checkbox was deliberately cleared.
    def valid_staff_access?
      return true if @user.admin? || @user.super_admin? || @user.confirmation_agent?

      @user.errors.add(:base, "Supervisors need Admin access. Select Admin access or choose Confirmation agent.")
      false
    end

    def user_params_without_pay
      params.require(:user).permit(:email, :name, :admin, :confirmation_role, :password, :password_confirmation)
    end

    # The form takes the per-delivery rate in MAD; it is stored as integer cents.
    def user_params
      permitted = user_params_without_pay
      rate = params.dig(:user, :pay_per_delivery)
      permitted[:pay_per_delivery_cents] = parse_mad_cents(rate) if rate.present?
      penalty = params.dig(:user, :return_penalty)
      permitted[:return_penalty_cents] = penalty.present? ? parse_mad_cents(penalty) : 0 if params[:user]&.key?(:return_penalty)
      permitted
    end
  end
end
