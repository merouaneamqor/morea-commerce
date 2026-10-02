module Admin
  class PagesController < BaseController
    before_action :set_page, only: %i[edit update destroy]

    def index
      @pages = current_store.pages.includes(:translations).order(:created_at)
    end

    def new
      @page = current_store.pages.new(published: true)
      @page.build_missing_translations!
    end

    def create
      @page = current_store.pages.new(page_params)
      if @page.save
        redirect_to edit_admin_page_path(@page), notice: "Page created."
      else
        @page.build_missing_translations!
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @page.build_missing_translations!
    end

    def update
      if @page.update(page_params)
        redirect_to edit_admin_page_path(@page), notice: "Page saved."
      else
        @page.build_missing_translations!
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @page.destroy!
      redirect_to admin_pages_path, notice: "Page deleted."
    end

    private

    def set_page
      @page = current_store.pages.includes(:translations).find_by!(slug: params[:id])
    end

    def page_params
      params.require(:page).permit(:slug, :published, translations_attributes: %i[id locale title body seo_title seo_description])
    end
  end
end
