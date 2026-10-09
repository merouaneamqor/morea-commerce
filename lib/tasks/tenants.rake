# frozen_string_literal: true

namespace :tenants do
  desc "Create a store tenant and its first admin (TENANT_SLUG, TENANT_NAME, ADMIN_EMAIL, ADMIN_PASSWORD)"
  task create: :environment do
    slug = ENV.fetch("TENANT_SLUG") { abort "Set TENANT_SLUG (e.g. morea)" }
    name = ENV.fetch("TENANT_NAME") { abort "Set TENANT_NAME" }
    email = ENV.fetch("ADMIN_EMAIL") { abort "Set ADMIN_EMAIL" }
    password = ENV.fetch("ADMIN_PASSWORD") { abort "Set ADMIN_PASSWORD" }

    store = Store.find_or_initialize_by(slug: slug.to_s.strip.downcase)
    store.name = name
    store.currency ||= "MAD"
    store.save!

    user = store.users.find_or_initialize_by(email: email.to_s.strip.downcase)
    user.name ||= name
    user.password = password
    user.password_confirmation = password
    user.admin = true
    user.save!

    store.install_online_store_defaults! unless store.home_sections.exists? || store.menu_items.exists?

    puts "Store: #{store.name} (#{store.slug})"
    puts "URL:   #{store.origin}"
    puts "Admin: #{user.email} / (password set)"
  end
end
