# frozen_string_literal: true

namespace :stores do
  desc "Generate an API token for a store (stores:api_token[slug])"
  task :api_token, [ :slug ] => :environment do |_task, args|
    slug = args[:slug].presence || ENV["STORE_SLUG"]
    abort "Usage: bin/rails stores:api_token[slug]" if slug.blank?

    store = Store.find_by(slug: slug.to_s.strip.downcase)
    abort "Store not found: #{slug}" unless store

    token = store.generate_api_token!
    puts "Store: #{store.slug}"
    puts "Token: #{token}"
    puts "Ends:  #{store.api_token_last_four}"
  end
end
