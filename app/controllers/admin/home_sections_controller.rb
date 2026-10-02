module Admin
  class HomeSectionsController < BaseController
    before_action :set_section, only: %i[edit update destroy move toggle]

    def index
      current_store.install_online_store_defaults! unless current_store.home_sections.exists?
      @sections = current_store.home_sections.ordered.includes(:translations)
    end

    def new
      kind = HomeSection::KINDS.key?(params[:kind]) ? params[:kind] : "image_with_text"
      @section = current_store.home_sections.new(kind: kind)
      @section.build_missing_translations!
    end

    def create
      @section = current_store.home_sections.new(section_params.merge(kind: params.dig(:home_section, :kind)))
      if @section.save
        redirect_to admin_home_sections_path, notice: "#{@section.label} added."
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
        @section.image.purge_later if params.dig(:home_section, :remove_image) == "1" && params.dig(:home_section, :image).blank?
        redirect_to edit_admin_home_section_path(@section), notice: "Section saved."
      else
        @section.build_missing_translations!
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @section.destroy!
      redirect_to admin_home_sections_path, notice: "Section removed."
    end

    def move
      @section.move!(params[:direction])
      redirect_to admin_home_sections_path
    end

    def toggle
      @section.update!(visible: !@section.visible)
      redirect_to admin_home_sections_path, notice: @section.visible ? "Section shown." : "Section hidden."
    end

    private

    def set_section
      @section = current_store.home_sections.includes(:translations).find(params[:id])
    end

    def section_params
      params.require(:home_section).permit(
        :visible, :image, :image_url, :link, :custom_url, :collection_id, :limit, :image_position,
        translations_attributes: %i[id locale heading subheading body button_label]
      )
    end
  end
end
