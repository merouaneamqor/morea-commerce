module Admin
  class ProductsController < BaseController
    before_action :set_product, only: %i[show edit update destroy]

    def index
      @products = current_store.products.includes(:translations).order(:position, :name)
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
        attach_images
        redirect_to edit_admin_product_path(@product), notice: "Product created."
      else
        @product.build_missing_translations!
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @product.build_missing_translations!
    end

    def update
      if @product.update(product_params)
        attach_images
        redirect_to edit_admin_product_path(@product), notice: "Product saved."
      else
        @product.build_missing_translations!
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @product.destroy!
      redirect_to admin_products_path, notice: "Product deleted."
    end

    private

    def set_product
      @product = current_store.products.includes(:translations).find(params[:id])
    end

    def product_params
      params.require(:product).permit(
        :slug, :status, :price_dh, :compare_at_dh, :currency,
        :sku, :stock, :track_inventory, :featured, :position,
        :image_url, :detail_image_url,
        collection_ids: [],
        translations_attributes: [
          :id, :locale, :name, :short_description, :story, :material, :fit, :movement,
          :dimensions, :origin, :care, :seo_title, :seo_description
        ]
      )
    end

    def attach_images
      return unless params[:product][:images].present?

      Array(params[:product][:images]).reject(&:blank?).each do |image|
        @product.images.attach(image)
      end
    end
  end
end
