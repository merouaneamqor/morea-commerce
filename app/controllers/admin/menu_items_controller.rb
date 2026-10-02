module Admin
  class MenuItemsController < BaseController
    before_action :set_item, only: %i[edit update destroy move]

    def index
      current_store.install_online_store_defaults! unless current_store.menu_items.exists?
      @items = current_store.menu_items.ordered.includes(:translations).group_by(&:menu)
    end

    def new
      menu = MenuItem::MENUS.key?(params[:menu]) ? params[:menu] : "header"
      @item = current_store.menu_items.new(menu: menu)
      @item.build_missing_translations!
    end

    def create
      @item = current_store.menu_items.new(item_params)
      if @item.save
        redirect_to admin_menu_items_path, notice: "Menu item added."
      else
        @item.build_missing_translations!
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @item.build_missing_translations!
    end

    def update
      if @item.update(item_params)
        redirect_to admin_menu_items_path, notice: "Menu item saved."
      else
        @item.build_missing_translations!
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @item.destroy!
      redirect_to admin_menu_items_path, notice: "Menu item removed."
    end

    def move
      @item.move!(params[:direction])
      redirect_to admin_menu_items_path
    end

    private

    def set_item
      @item = current_store.menu_items.includes(:translations).find(params[:id])
    end

    def item_params
      params.require(:menu_item).permit(:menu, :link, :custom_url, translations_attributes: %i[id locale label])
    end
  end
end
