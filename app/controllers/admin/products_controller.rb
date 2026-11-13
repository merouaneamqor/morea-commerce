module Admin
  class ProductsController < BaseController
    before_action :set_product, only: %i[show edit update destroy]

    # The products of the workspace: those it made and those of its connected stores that are switched on. The store
    # chooser narrows the list to one store (or to the manual ones); a switched-off store has no products here.
    def index
      @connections = current_store.store_connections.where(active: true).order(:name)
      visible = current_store.products.visible
      @counts = visible.group(:store_connection_id).count
      @source = params[:source].to_s
      scope = visible
      scope = scope.native if @source == "manual"
      scope = scope.where(store_connection_id: @connections.find(@source).id) if @source.match?(/\A\d+\z/)
      @products = scope.includes(:translations, :product_variants, :store_connection, images_attachments: :blob).order(:position, :name)
    end

    def show
      redirect_to edit_admin_product_path(@product)
    end

    def new
      @product = current_store.products.new(status: "draft", currency: current_store.currency, stock: 0)
      @product.build_missing_translations!
    end

    def create
      @product = current_store.products.new(product_params)
      if @product.save
        update_images
        redirect_to edit_admin_product_path(@product), notice: "Product created."
      else
        @product.build_missing_translations!
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @product.build_missing_translations!
      @inventory_movements = @product.inventory_movements.includes(:product_variant, :order).order(created_at: :desc).limit(50)
    end

    def update
      if @product.update(product_params)
        update_images
        redirect_to edit_admin_product_path(@product), notice: "Product saved."
      else
        @product.build_missing_translations!
        @inventory_movements = @product.inventory_movements.includes(:product_variant, :order).order(created_at: :desc).limit(50)
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @product.destroy!
      redirect_to admin_products_path, notice: "Product deleted."
    end

    private

    def set_product
      @product = current_store.products.includes(:translations).find_by!(slug: params[:id])
    end

    def product_params
      params.require(:product).permit(
        :slug, :status, :price_dh, :compare_at_dh, :cost_dh, :currency,
        :sku, :stock, :track_inventory, :featured, :position,
        collection_ids: [],
        translations_attributes: [
          :id, :locale, :name, :short_description, :story, :material, :fit, :movement,
          :dimensions, :origin, :care, :seo_title, :seo_description
        ]
      )
    end

    # Remove ticked images, attach uploads, then save the dragged order (new uploads go last)
    def update_images
      remove_ids = Array(params[:product][:remove_image_ids]).compact_blank.map(&:to_i)
      @product.images.where(id: remove_ids).find_each(&:purge_later) if remove_ids.any?

      images = Array(params[:product][:images]).compact_blank
      @product.images.attach(images) if images.any?

      ids = @product.images_attachments.reload.order(:id).ids
      order = Array(params[:product][:image_order]).compact_blank.map(&:to_i) & ids
      @product.update_column(:image_order, order + (ids - order))
    end
  end
end
