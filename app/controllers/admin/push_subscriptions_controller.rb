module Admin
  # Browsers opt in to order alerts for the signed-in staff member. One row per
  # browser endpoint; the browser's current user always owns it.
  class PushSubscriptionsController < BaseController
    before_action :require_store_context!

    def create
      subscription = PushSubscription.find_or_initialize_by(endpoint: subscription_params[:endpoint])
      subscription.assign_attributes(store: current_store, user: current_user,
        p256dh: subscription_params.dig(:keys, :p256dh), auth: subscription_params.dig(:keys, :auth))

      if subscription.save
        head :created
      else
        render json: { errors: subscription.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      PushSubscription.where(store: current_store, user: current_user, endpoint: subscription_params[:endpoint]).destroy_all
      head :no_content
    end

    private

    def require_store_context!
      head :not_found unless current_store
    end

    def subscription_params
      params.require(:subscription).permit(:endpoint, keys: %i[p256dh auth])
    end
  end
end
