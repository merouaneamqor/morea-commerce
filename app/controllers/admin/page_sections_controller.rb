# frozen_string_literal: true

module Admin
  class PageSectionsController < BaseController
    before_action :set_page
    before_action :set_section, only: %i[edit update destroy move toggle]

    def index
      unless @page.landing?
        redirect_to edit_admin_page_path(@page), notice: "Switch the page template to Landing page to edit sections."
        return
      end

      @sections = @page.page_sections.ordered.includes(:translations)
    end

    def new
      kind = PageSection::KINDS.key?(params[:kind]) ? params[:kind] : "image_with_text"
      @section = @page.page_sections.new(kind: kind)
      @section.build_missing_translations!
    end

    def create
      @section = @page.page_sections.new(section_params.merge(kind: params.dig(:page_section, :kind)))
      if @section.save
        redirect_to admin_page_sections_path(@page), notice: "#{@section.label} added."
      else
        @section.build_missing_translations!
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @section.build_missing_translations!
    end

    def update
      if @section.update(section_params)
        @section.image.purge_later if params.dig(:page_section, :remove_image) == "1" && params.dig(:page_section, :image).blank?
        redirect_to edit_admin_page_section_path(@page, @section), notice: "Section saved."
      else
        @section.build_missing_translations!
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @section.destroy!
      redirect_to admin_page_sections_path(@page), notice: "Section removed."
    end

    def move
      @section.move!(params[:direction])
      redirect_to admin_page_sections_path(@page)
    end

    def toggle
      @section.update!(visible: !@section.visible)
      redirect_to admin_page_sections_path(@page), notice: @section.visible? ? "Section shown." : "Section hidden."
    end

    private

    def set_page
      @page = current_store.pages.includes(:translations).find_by!(slug: params[:page_id])
    end

    def set_section
      @section = @page.page_sections.includes(:translations).find(params[:id])
    end

    def section_params
      params.require(:page_section).permit(
        :visible, :image, :image_url, :link, :custom_url, :collection_id, :limit, :image_position,
        translations_attributes: %i[id locale heading subheading body button_label]
      )
    end
  end
end
