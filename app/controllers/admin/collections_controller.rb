module Admin
  class CollectionsController < BaseController
    before_action :set_collection, only: %i[edit update destroy]

    def index
      @collections = current_store.collections.includes(:translations).order(:position, :name)
    end

    def new
      @collection = current_store.collections.new(published: true)
      @collection.build_missing_translations!
    end

    def create
      @collection = current_store.collections.new(collection_params)
      if @collection.save
        sync_products
        redirect_to admin_collections_path, notice: "Collection created."
      else
        @collection.build_missing_translations!
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @collection.build_missing_translations!
    end

    def update
      if @collection.update(collection_params)
        sync_products
        redirect_to edit_admin_collection_path(@collection), notice: "Collection saved."
      else
        @collection.build_missing_translations!
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @collection.destroy!
      redirect_to admin_collections_path, notice: "Collection deleted."
    end

    private

    def set_collection
      @collection = current_store.collections.includes(:translations).find_by!(slug: params[:id])
    end

    def collection_params
      params.require(:collection).permit(
        :slug, :published, :position,
        translations_attributes: %i[id locale name subtitle description]
      )
    end

    def sync_products
      ids = Array(params[:collection][:product_ids]).reject(&:blank?).map(&:to_i)
      @collection.product_ids = ids
    end
  end
end
