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
        # The payout settles the unpaid earnings and subtracts the pending deductions, oldest first, as many
        # as the earnings cover (a deduction is never split); the rest waits for the next payout.
        AgentPayment.transaction do
          payment = AgentPayment.create!(store: current_store, user: @user, paid_by: current_user, amount_cents: summary.unpaid, paid_at: Time.current)
          covered = 0
          AgentDeduction.pending.where(store: current_store, user: @user).order(:created_at, :id).lock.each do |deduction|
            break if covered + deduction.amount_cents > summary.unpaid

            deduction.update!(status: "applied", agent_payment: payment)
            covered += deduction.amount_cents
          end
          payment.update!(deductions_cents: covered)
        end
        redirect_to admin_users_path, notice: t("admin.team.paid", name: @user.name.presence || @user.email)
      end
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
