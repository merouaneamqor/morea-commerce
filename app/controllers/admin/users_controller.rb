module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[edit update destroy pay]

    def index
      @users = current_store.users.order(:email)
      earnings = Team::AgentEarnings.new(store: current_store, range: Time.current.beginning_of_month..Time.current)
      @summaries = @users.to_h { |user| [ user.id, earnings.summary_for(user) ] }
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

      if @user.update(attrs)
        redirect_to admin_users_path, notice: "Staff account saved."
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

    # Records one payment covering everything earned and not yet paid.
    def pay
      summary = Team::AgentEarnings.new(store: current_store, range: Time.current.beginning_of_month..Time.current).summary_for(@user)
      if summary.unpaid.zero?
        redirect_to admin_users_path, alert: t("admin.team.nothing_to_pay")
      else
        AgentPayment.create!(store: current_store, user: @user, paid_by: current_user, amount_cents: summary.unpaid, paid_at: Time.current)
        redirect_to admin_users_path, notice: t("admin.team.paid", name: @user.name.presence || @user.email)
      end
    end

    private

    def set_user
      @user = current_store.users.find(params[:id])
    end

    def user_params_without_pay
      params.require(:user).permit(:email, :name, :admin, :confirmation_role, :password, :password_confirmation)
    end

    # The form takes the per-delivery rate in MAD; it is stored as integer cents.
    def user_params
      permitted = user_params_without_pay
      rate = params.dig(:user, :pay_per_delivery)
      permitted[:pay_per_delivery_cents] = parse_mad_cents(rate) if rate.present?
      permitted
    end
  end
end
