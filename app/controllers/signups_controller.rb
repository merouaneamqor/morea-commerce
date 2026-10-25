# frozen_string_literal: true

class SignupsController < ApplicationController
  layout "auth"
  before_action :require_apex!
  before_action :secure_verification_response, only: %i[verify confirm]
  rate_limit to: 10, within: 1.hour, only: %i[create resend], with: -> { render_throttled }

  def new
    @registration = Registration.new
  end

  def create
    # Bots receive the same response without creating records or sending mail.
    return redirect_to(signup_thanks_path) if params[:website].present?

    @registration = Registration.new(signup_params.merge(locale: I18n.locale.to_s))
    # Structural errors behave identically for known and unknown addresses.
    # Never expose the uniqueness validator in an invalid form response.
    @registration.valid?
    @registration.errors.delete(:email, :taken)
    if @registration.errors.any?
      render :new, status: :unprocessable_entity
    elsif duplicate_identity?
      redirect_to signup_thanks_path
    else
      @registration.verification_sent_at = Time.current
      if @registration.save
        RegistrationMailer.verification(@registration).deliver_later
        redirect_to signup_thanks_path
      elsif duplicate_identity?
        redirect_to signup_thanks_path
      else
        @registration.errors.delete(:email, :taken)
        render :new, status: :unprocessable_entity
      end
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to signup_thanks_path
  end

  def thanks
  end

  # GET only previews the confirmation; email scanners cannot activate accounts.
  def verify
    @token = params[:token].to_s
    @registration = Registration.find_by_token_for(:email_verification, @token)
    @registration = nil if @registration&.verified?
    render :verify, status: @registration ? :ok : :unprocessable_entity
  end

  def confirm
    result = Registrations::Confirm.call(
      token: params[:token], password: params[:password], password_confirmation: params[:password_confirmation]
    )
    if result.is_a?(User)
      user = result
      reset_session
      session[:user_id] = user.id
      session[:session_version] = user.session_version
      session[:admin_mode] = "store"
      redirect_to admin_root_path, notice: t("registration.verified")
    else
      @token = params[:token].to_s
      @registration = result if result.is_a?(Registration)
      render :verify, status: :unprocessable_entity
    end
  end

  def resend
    email = params[:email].to_s.strip.downcase
    registration = Registration.find_by(email: email)
    if registration&.resend_verification!
      RegistrationMailer.verification(registration).deliver_later
    end
    # Generic response also covers unknown, verified and rate-limited addresses.
    redirect_to signup_thanks_path, notice: t("registration.resend_notice")
  end

  private

  def require_apex!
    render template: "stores/missing", layout: "bare", status: :not_found unless Store.apex_host?(request.host)
  end

  def secure_verification_response
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "no-referrer"
  end

  def signup_params
    params.require(:registration).permit(:business_name, :email)
  end

  def duplicate_identity?
    @registration.email.present? &&
      (Registration.exists?(email: @registration.email) || User.exists?(email: @registration.email))
  end

  def render_throttled
    @registration = Registration.new
    flash.now[:alert] = t("signup.throttled")
    render :new, status: :too_many_requests
  end
end
