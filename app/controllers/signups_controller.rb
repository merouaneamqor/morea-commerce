# frozen_string_literal: true

# Public "request access" form on the platform apex. Creates a pending AccessRequest only.
class SignupsController < ApplicationController
  layout "auth"
  before_action :require_apex!

  def new
    @access_request = AccessRequest.new
  end

  def create
    return render_throttled if AccessRequest.throttled?(request.remote_ip)
    # Honeypot: bots fill the hidden field. Answer as if it worked, store nothing.
    return redirect_to(signup_thanks_path) if params[:website].present?

    @access_request = AccessRequest.new(signup_params.merge(locale: I18n.locale.to_s, ip: request.remote_ip))
    if @access_request.save
      AccessRequestNotifyJob.perform_later(@access_request.id)
      redirect_to signup_thanks_path
    elsif duplicate_pending?
      # Same answer as success so the form cannot be used to probe which emails already asked.
      redirect_to signup_thanks_path
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to signup_thanks_path
  end

  def thanks
  end

  private

  def require_apex!
    render template: "stores/missing", layout: "bare", status: :not_found unless Store.apex_host?(request.host)
  end

  def signup_params
    params.require(:access_request).permit(:store_name, :email, :phone, :storefront_enabled)
  end

  def duplicate_pending?
    @access_request.errors.attribute_names == [ :email ] && AccessRequest.pending.exists?(email: @access_request.email)
  end

  def render_throttled
    @access_request = AccessRequest.new
    flash.now[:alert] = t("signup.throttled")
    render :new, status: :too_many_requests
  end
end
