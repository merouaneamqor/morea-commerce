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

      if @user.update(attrs)
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
        @user.destroy!
        redirect_to admin_users_path, notice: "Staff account deleted."
      end
    end

    private

    def set_user
      @user = current_store.users.find(params[:id])
    end

    def user_params
      params.require(:user).permit(:email, :name, :admin, :password, :password_confirmation)
    end
  end
end
