namespace :morea do
  namespace :shopify do
    desc "Register the order webhook and import recent Shopify COD orders for every authorized connection"
    task sync: :environment do
      ShopifyOrdersSyncJob.perform_now
    end
  end
end
