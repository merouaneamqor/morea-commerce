module OnlineStoreHelper
  # Resolve a StoreLinkable reference to a localized storefront path
  def store_link_path(link)
    case link.to_s
    when "", nil then nil
    when "home" then localized_root_path
    when "collections" then collections_path
    when "cart" then cart_path
    when "track" then track_orders_path
    when /\Acollection:([\w-]+)\z/ then collection_path($1)
    when /\Aproduct:([\w-]+)\z/ then product_path($1)
    when /\Apage:([\w-]+)\z/ then page_path($1)
    else link
    end
  end

  def external_link?(link)
    link.to_s.start_with?("http")
  end

  def store_menu(menu)
    @store_menus ||= {}
    @store_menus[menu] ||= begin
      items = current_store ? current_store.menu_items.in_menu(menu).includes(:translations).to_a : []
      if items.empty? && current_store && !current_store.menu_items.exists?
        # Pages only exist once defaults are installed, so leave their links out until then
        items = OnlineStoreDefaults.new(current_store).menu_items.select { |i| i.menu == menu && !i.link.start_with?("page:") }
      end
      items
    end
  end

  def store_menu_link(item, **options)
    href = store_link_path(item.link)
    return if href.blank?

    options = options.merge(target: "_blank", rel: "noopener noreferrer") if external_link?(item.link)
    link_to item.label, href, **options
  end

  # Grouped <select> options for the admin link picker
  def store_link_options(store, selected)
    groups = {
      "Store" => [ [ "Home page", "home" ], [ "All collections", "collections" ], [ "Cart", "cart" ], [ "Track order", "track" ] ],
      "Collections" => store.collections.order(:position).map { |c| [ c.name, "collection:#{c.slug}" ] },
      "Products" => store.products.order(:name).map { |p| [ p.name, "product:#{p.slug}" ] },
      "Pages" => store.pages.map { |p| [ p.title, "page:#{p.slug}" ] },
      "Other" => [ [ "Custom URL…", StoreLinkable::CUSTOM ] ]
    }
    known = groups.values.flatten(1).map(&:last)
    selected = StoreLinkable::CUSTOM if selected.present? && known.exclude?(selected)
    grouped_options_for_select(groups, selected)
  end

  # Collection tiles for the collection list section: editorial cover if present,
  # else a product image not already used by an earlier tile
  def collection_tiles(collections)
    used = []
    collections.filter_map do |collection|
      cover_url = collection_cover_url(collection)
      unless cover_url
        products = collection.products.active.to_a
        product = products.find { |p| used.exclude?(p.id) } || products.first
        next unless product

        used << product.id
        cover_url = product_image_url(product)
      end
      [ collection, cover_url ]
    end
  end
end
