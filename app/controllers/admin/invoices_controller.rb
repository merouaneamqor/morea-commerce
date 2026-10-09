# frozen_string_literal: true

module Admin
  class InvoicesController < BaseController
    layout "admin_platform"
    before_action :require_super_admin!
    before_action :enter_platform_mode
    before_action :set_store
    before_action :set_invoice, only: %i[show issue mark_paid void]

    def index
      @invoices = @store.invoices.order(created_at: :desc)
    end

    def show
    end

    def new
      @invoice = Invoice.build_for_store(@store)
    end

    def create
      @invoice = @store.invoices.new(invoice_params)
      if @invoice.save
        redirect_to admin_tenant_invoice_path(@store, @invoice), notice: "Draft invoice #{@invoice.number} created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def issue
      @invoice.issue!
      redirect_to admin_tenant_invoice_path(@store, @invoice), notice: "Invoice #{@invoice.number} issued."
    rescue ActiveRecord::RecordInvalid
      redirect_to admin_tenant_invoice_path(@store, @invoice), alert: "Cannot issue this invoice."
    end

    def mark_paid
      @invoice.mark_paid!
      redirect_to admin_tenant_invoice_path(@store, @invoice), notice: "Invoice #{@invoice.number} marked paid."
    rescue ActiveRecord::RecordInvalid
      redirect_to admin_tenant_invoice_path(@store, @invoice), alert: "Cannot mark this invoice paid."
    end

    def void
      @invoice.void!
      redirect_to admin_tenant_invoice_path(@store, @invoice), notice: "Invoice #{@invoice.number} voided."
    rescue ActiveRecord::RecordInvalid
      redirect_to admin_tenant_invoice_path(@store, @invoice), alert: "Cannot void this invoice."
    end

    private

    def enter_platform_mode
      session[:admin_mode] = "platform"
    end

    def set_store
      @store = Store.find(params[:tenant_id])
    end

    def set_invoice
      @invoice = @store.invoices.find(params[:id])
    end

    def invoice_params
      params.require(:invoice).permit(
        :amount_dh, :billing_interval, :period_starts_on, :period_ends_on, :due_on, :notes
      )
    end
  end
end
