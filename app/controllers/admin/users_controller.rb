module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[edit update destroy]

    def index
      @users = current_store.users.order(:email)
    end

    def new
      @user = current_store.users.new(admin: true)
    end

    def create
      @user = current_store.users.new(user_params)
      if @user.save
        audit("staff.created", @user)
        redirect_to admin_users_path, notice: "Staff account created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      attrs = user_params
      attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?

      changed_password = attrs[:password].present?
      if @user.update(attrs)
        audit("staff.updated", @user, changed: @user.previous_changes.keys & %w[email name admin])
        if changed_password
          AdminSession.revoke_all_for(@user, except: (current_admin_session if @user == current_user))
          audit("auth.password_changed", @user)
        end
        redirect_to admin_users_path, notice: "Staff account saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @user == current_user
        redirect_to admin_users_path, alert: "You cannot delete your own account."
      elsif current_store.users.where(admin: true).where.not(id: @user.id).none?
        redirect_to admin_users_path, alert: "Keep at least one admin account."
      else
        audit("staff.deleted", @user)
        @user.destroy!
        redirect_to admin_users_path, notice: "Staff account deleted."
      end
    end

    private

    def audit(action, user, **metadata)
      Audit.record(action, actor: current_user, store: current_store, request: request, subject: user,
        metadata: metadata.merge(target: user.name.presence || user.email))
    end

    def set_user
      @user = current_store.users.find(params[:id])
    end

    def user_params
      params.require(:user).permit(:email, :name, :admin, :password, :password_confirmation)
    end
  end
end
