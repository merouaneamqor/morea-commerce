module Admin
  class OnlineStoreController < BaseController
    def show
      return redirect_to(admin_platform_path) if super_admin? && !current_store
      return head(:not_found) unless current_store

      @store = current_store
      @storefront_counts = {
        products: current_store.products.active.count,
        collections: current_store.collections.published.count,
        home_sections: current_store.home_sections.visible.count,
        navigation: current_store.menu_items.count,
        pages: current_store.pages.published.count
      }
      @ready_steps = @storefront_counts.values.count(&:positive?)
    end
  end
end
