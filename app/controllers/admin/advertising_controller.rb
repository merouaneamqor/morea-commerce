module Admin
  class AdvertisingController < BaseController
    before_action :require_workspace!

    def show
      @summary = AdvertisingSummary.new(store: current_store, start_date: params[:start_date], end_date: params[:end_date], sort: params[:sort])
      @report ||= if params[:report_campaign_id].present?
        scoped_campaigns.find(params[:report_campaign_id]).advertising_performances.find_or_initialize_by(date: (Date.iso8601(params[:report_date].to_s) rescue Date.current))
      else
        AdvertisingPerformance.new(date: Date.current)
      end
    end

    def accounts
      account = AdvertisingAccount.new(params.require(:account).permit(:name, :provider))
      account.store = current_store
      save_record(account)
    end

    def update_account
      account = scoped_accounts.find(params[:id])
      # This is a local reporting state; it never changes provider delivery.
      account.active = ActiveModel::Type::Boolean.new.cast(params.require(:active))
      save_record(account)
    end

    def campaigns
      account = scoped_accounts.find(params.require(:campaign)[:advertising_account_id])
      save_record(account.advertising_campaigns.new(params.require(:campaign).permit(:name)))
    end

    def update_campaign
      campaign = scoped_campaigns.find(params[:id])
      campaign.active = ActiveModel::Type::Boolean.new.cast(params.require(:active))
      save_record(campaign)
    end

    def performance
      input = params.require(:performance)
      campaign = scoped_campaigns.find(input[:advertising_campaign_id])
      date = Date.iso8601(input[:date].to_s)
      record = campaign.advertising_performances.find_or_initialize_by(date: date)
      record.assign_attributes(input.permit(:confirmed_orders, :delivered_orders, :clicks, :impressions))
      %i[spend delivered_revenue fulfillment_cost].each do |field|
        value = BigDecimal(input.require(field).to_s) * 100
        raise ArgumentError unless value.finite? && value == value.round
        record.public_send("#{field}_cents=", value.to_i)
      end
      save_record(record)
    rescue Date::Error, ArgumentError
      redirect_to admin_advertising_path, alert: "Enter a valid reporting date and MAD amounts with at most two decimals."
    end

    private

    def require_workspace!
      head :not_found unless current_store
    end

    def scoped_accounts
      AdvertisingAccount.where(store: current_store)
    end

    def scoped_campaigns
      AdvertisingCampaign.where(advertising_account_id: scoped_accounts.select(:id))
    end

    def save_record(record)
      if record.save
        redirect_to admin_advertising_path, notice: "Advertising report saved."
      else
        @error = record.errors.full_messages.to_sentence
        @report = record if record.is_a?(AdvertisingPerformance)
        show
        render :show, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotUnique
      redirect_to admin_advertising_path, alert: "This reporting day was updated concurrently. Please reload and try again."
    end
  end
end
