# frozen_string_literal: true

class PasswordResetsController < ApplicationController
  layout "auth"
  before_action :require_apex!
  before_action :secure_response
  rate_limit to: 10, within: 1.hour, only: %i[create], with: -> { render_throttled }

  def new
  end

  def create
    user = reset_user
    if user&.can_sign_in? && reserve_delivery(user)
      PasswordResetMailer.instructions(user, I18n.locale.to_s).deliver_later
    end
    redirect_to new_password_reset_path, notice: t("password_reset.requested")
  end

  def edit
    @token = params[:token].to_s
    @user = User.find_by_token_for(:password_reset, @token)
    @user = nil unless @user&.can_sign_in?
    render :edit, status: @user ? :ok : :unprocessable_entity
  end

  def update
    @token = params[:token].to_s
    @user = User.find_by_token_for(:password_reset, @token)
    success = false
    if @user
      @user.with_lock do
        current = User.find_by_token_for(:password_reset, @token)
        if current&.id == @user.id && @user.can_sign_in?
          @user.assign_attributes(password: params[:password], password_confirmation: params[:password_confirmation])
          # Invalidate every existing authenticated session together with this reset.
          @user.session_version += 1
          success = @user.save(context: :password_reset)
        else
          @user = nil
        end
      end
    end
    if success
      reset_session
      redirect_to admin_login_path(locale: I18n.locale), notice: t("password_reset.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def require_apex!
    render template: "stores/missing", layout: "bare", status: :not_found unless Store.apex_host?(request.host)
  end

  def secure_response
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "no-referrer"
  end

  def reset_user
    email = params[:email].to_s.strip.downcase
    return if email.blank?

    if params[:workspace].present?
      store = Store.find_by(slug: params[:workspace].to_s.strip.downcase)
      store&.users&.active&.find_by(email: email)
    else
      candidates = User.active.where(email: email).where("admin = TRUE OR super_admin = TRUE").limit(2).to_a
      candidates.first if candidates.one?
    end
  end

  def reserve_delivery(user)
    # Avoid repeated messages across request IPs without putting email addresses in cache keys.
    Rails.cache.write("password-reset-delivery:#{user.id}", true, expires_in: 2.minutes, unless_exist: true)
  end

  def render_throttled
    flash.now[:alert] = t("password_reset.throttled")
    render :new, status: :too_many_requests
  end
end
