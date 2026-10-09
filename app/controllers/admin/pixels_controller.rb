# frozen_string_literal: true

module Admin
  class PixelsController < BaseController
    def edit
      @store = current_store
    end

    def update
      @store = current_store
      if @store.update(pixel_params)
        redirect_to edit_admin_pixels_path, notice: "Pixel settings saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def pixel_params
      params.require(:store).permit(:meta_pixel_id, :tiktok_pixel_id)
    end
  end
end
