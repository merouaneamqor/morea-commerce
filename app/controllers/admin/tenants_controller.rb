# frozen_string_literal: true

module Admin
  # Provision new store tenants. The store list lives on the platform dashboard.
  class TenantsController < BaseController
    layout "admin_platform"
    before_action :require_super_admin!
    before_action :enter_platform_mode, only: %i[index new create edit update]
    before_action :set_store, only: %i[edit update enter]

    def index
      redirect_to admin_platform_path
    end

    def new
      @store = Store.new(
        currency: "MAD",
        billing_interval: "monthly",
        billing_status: "trial",
        billing_amount_cents: 0
      )
    end

    def create
      @store = Store.new(store_params)
      password = params.require(:admin).permit(:password)[:password].to_s
      email = params.require(:admin).permit(:email)[:email].to_s.strip.downcase

      if password.blank? || email.blank?
        @store.errors.add(:base, "First admin email and password are required.")
        return render :new, status: :unprocessable_entity
      end

      ActiveRecord::Base.transaction do
        @store.save!
        @store.users.create!(
          email: email,
          name: "#{@store.name} Admin",
          password: password,
          password_confirmation: password,
          admin: true
        )
        @store.install_online_store_defaults!
      end

      redirect_to admin_platform_path, notice: "Store #{@store.name} created. Open it at #{@store.origin}/admin"
    rescue ActiveRecord::RecordInvalid
      render :new, status: :unprocessable_entity
    end

    def edit
    end

    def update
      if @store.update(billing_params)
        redirect_to admin_platform_path, notice: "Billing updated for #{@store.name}."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Switch into store-ops mode, then open that store's admin (may be another subdomain).
    def enter
      session[:admin_mode] = "store"
      if current_store&.id == @store.id
        redirect_to admin_root_path
      else
        redirect_to "#{@store.origin}/admin", allow_other_host: true
      end
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
        :name, :slug, :email, :phone, :currency,
        :billing_interval, :billing_status, :billing_amount_dh, :billing_period_ends_on
      )
    end

    def billing_params
      params.require(:store).permit(
        :billing_interval, :billing_status, :billing_amount_dh, :billing_period_ends_on
      )
    end
  end
end
