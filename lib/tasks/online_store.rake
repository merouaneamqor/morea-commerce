namespace :morea do
  namespace :online_store do
    desc "Install default home sections, pages and menus for stores that have none (idempotent)"
    task install: :environment do
      Store.find_each do |store|
        store.install_online_store_defaults!
        puts "#{store.name}: #{store.home_sections.count} sections, #{store.pages.count} pages, #{store.menu_items.count} menu items"
      end
    end
  end
end
