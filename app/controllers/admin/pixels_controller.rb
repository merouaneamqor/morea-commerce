# frozen_string_literal: true

module Admin
  # Measurement tags for the public storefront: Meta Events Manager, TikTok, Google Analytics.
  # Scripts load only after the visitor accepts measurement cookies.
  class PixelsController < BaseController
    def edit
      @store = current_store
    end

    def update
      @store = current_store
      if @store.update(pixel_params)
        redirect_to seller_pixels_path, notice: t("pixels.saved"), status: :see_other
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def pixel_params
      params.require(:store).permit(:meta_pixel_id, :tiktok_pixel_id, :google_analytics_id)
    end
  end
end
