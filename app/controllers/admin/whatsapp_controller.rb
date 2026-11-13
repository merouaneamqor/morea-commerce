module Admin
  # WhatsApp Business (Cloud API) settings of the store, for the owner: the connected numbers, the automatic message sent to the customer when an order
  # arrives (with keywords such as {{nom_client}}), a test send, and the log of the messages. Every query is scoped to the store; the token is never shown back.
  class WhatsappController < BaseController
    before_action :require_store_context!
    before_action :require_owner!
    before_action :set_account, only: %i[update destroy test]

    def show
      @accounts = current_store.whatsapp_accounts.order(:id)
      @messages = current_store.whatsapp_messages.recent.includes(:order, :whatsapp_account).limit(20)
    end

    def create
      account = current_store.whatsapp_accounts.new(create_params)
      account.new_order_message = nil
      if account.save
        redirect_to admin_whatsapp_path, notice: t("admin.whatsapp.account_added")
      else
        redirect_to admin_whatsapp_path, alert: account.errors.full_messages.to_sentence
      end
    end

    def update
      attrs = update_params
      attrs = attrs.except(:access_token) if attrs[:access_token].blank?
      if @account.update(attrs)
        redirect_to admin_whatsapp_path, notice: t("admin.whatsapp.saved")
      else
        redirect_to admin_whatsapp_path, alert: @account.errors.full_messages.to_sentence
      end
    end

    def destroy
      @account.destroy
      redirect_to admin_whatsapp_path, notice: t("admin.whatsapp.removed")
    end

    def test
      message = Whatsapp::OrderMessenger.deliver_test!(account: @account, to: params[:to])
      if message.status == "sent"
        redirect_to admin_whatsapp_path, notice: t("admin.whatsapp.test_sent")
      else
        redirect_to admin_whatsapp_path, alert: t("admin.whatsapp.test_failed", error: message.error)
      end
    end

    private

    def set_account
      @account = current_store.whatsapp_accounts.find(params[:id])
    end

    def require_store_context!
      head :not_found unless current_store
    end

    def require_owner!
      head :forbidden unless current_user&.super_admin? || current_user&.admin?
    end

    def create_params
      params.require(:whatsapp_account).permit(:name, :display_phone, :phone_number_id, :business_account_id, :access_token, :api_version)
    end

    def update_params
      params.require(:whatsapp_account).permit(:name, :display_phone, :business_account_id, :api_version, :access_token, :read_receipts, :auto_send_new_orders, :active, :new_order_message)
    end
  end
end
