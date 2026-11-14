# frozen_string_literal: true

# The public demo of the seller platform: one fictitious workspace ("Atlas Beauté") filled with realistic Moroccan COD data, shown read-only to visitors who press
# "Démo" on the landing page (DemoController signs them in as its owner or as one of its agents; Admin::BaseController then refuses every write).
#
# Everything here is made up: names, phones (0600000xxx), products, orders, fees, ad spend. It contains no credential and no connection to a carrier, to Meta or to
# WhatsApp, so no job or webhook can reach the outside. The data is dated relative to today and rebuilt when it gets old (see ensure!).
module Demo
  class Workspace
    SLUG = "atlas-beaute-demo"
    OWNER_EMAIL = "owner@demo.seallo.invalid"
    AGENT_EMAILS = %w[sara@demo.seallo.invalid youssef@demo.seallo.invalid hind@demo.seallo.invalid].freeze
    FRESH_FOR = 2.days
    # Bump when the generated data changes, so the workspace is rebuilt.
    DATA_VERSION = 3
    ORDER_COUNT = 380
    DAYS = 75

    FIRST_NAMES = %w[Amina Sara Meryem Imane Nora Salma Lina Yasmine Ghita Hanae Ikram Kawtar Zineb Asmae Youssef Omar Karim Hamza Anas Ayoub Mehdi Soufiane Reda Badr Hicham Khalid Walid Othmane].freeze
    LAST_NAMES = [ "El Idrissi", "Bennani", "Alaoui", "Amrani", "Lahlou", "Berrada", "Tazi", "Chraibi", "El Fassi", "Naciri", "Benjelloun", "Skalli", "Haddad", "Ouazzani", "Kettani", "Zniber" ].freeze
    PLACES = [
      [ "Casablanca", "Maarif", "12 rue des Fleurs" ], [ "Casablanca", "Ain Sebaa", "45 boulevard Moulay Slimane" ], [ "Rabat", "Agdal", "8 avenue Atlas" ], [ "Marrakech", "Guéliz", "24 rue Ibn Sina" ],
      [ "Tanger", "Malabata", "6 boulevard Pasteur" ], [ "Agadir", "Talborjt", "19 avenue Hassan II" ], [ "Fès", "Ville Nouvelle", "31 rue Lalla Aïcha" ], [ "Meknès", "Hamria", "15 avenue des FAR" ],
      [ "Kénitra", "Maamora", "9 rue Sebou" ], [ "Tétouan", "Centre", "18 avenue Mohammed V" ], [ "Oujda", "Al Qods", "22 boulevard Allal El Fassi" ], [ "Salé", "Hay Salam", "3 rue Oued Fès" ],
      [ "El Jadida", "Centre", "27 avenue Mohammed VI" ], [ "Béni Mellal", "Centre", "10 rue Tadla" ], [ "Nador", "Centre", "14 avenue Hassan II" ], [ "Mohammedia", "Centre", "5 rue Ibn Battouta" ]
    ].freeze
    CITY_WEIGHTS = [ 5, 3, 3, 3, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1 ].freeze

    # [name, short description, price MAD, cost MAD, variants [[name, price MAD or nil]], image file]
    CATALOG = [
      [ "Sérum Visage Éclat Vitamine C", "Sérum éclat à la vitamine C stabilisée, pour un teint lumineux.", 249, 72, [ [ "30 ml", nil ], [ "50 ml", 349 ] ], "serum" ],
      [ "Huile d'Argan Pure 100 ml", "Huile d'argan biologique pressée à froid, visage, corps et cheveux.", 189, 55, [], "argan" ],
      [ "Crème Hydratante Jour SPF 30", "Crème légère hydratante avec protection solaire quotidienne.", 159, 44, [], "creme" ],
      [ "Masque Purifiant au Rhassoul", "Masque à l'argile de rhassoul pour une peau nette et matifiée.", 99, 26, [], "masque" ],
      [ "Savon Noir Beldi 250 g", "Savon noir traditionnel à l'huile d'olive, gommage doux pour le hammam.", 59, 14, [], "savon" ],
      [ "Coffret Soin Visage Complet", "Nettoyant, sérum et crème dans un coffret cadeau.", 399, 128, [], "coffret" ],
      [ "Eau de Rose de Damas 200 ml", "Eau florale de rose, tonique et apaisante.", 79, 19, [], "rose" ],
      [ "Brosse Nettoyante Visage Silicone", "Brosse en silicone souple, nettoyage en profondeur.", 129, 31, [ [ "Rose", nil ], [ "Gris", nil ] ], "brosse" ]
    ].freeze

    DELIVERY_FEES = [ 3500, 3500, 3900, 4500 ].freeze

    class << self
      def demo_store?(store)
        store.present? && store.slug == SLUG
      end

      def store
        Store.find_by(slug: SLUG)
      end

      # The demo workspace, built the first time and rebuilt when its newest order is older than FRESH_FOR (so the charts always end today).
      def ensure!
        current = store
        return current if current && current.orders.where("number LIKE ?", "ATL#{DATA_VERSION}-%").exists? && current.orders.maximum(:created_at).to_i > FRESH_FOR.ago.to_i

        new.build!
      end
    end

    def initialize(now: Time.current)
      @now = now
      @rng = Random.new(20_260)
    end

    def build!
      wipe!(Store.find_by(slug: SLUG))
      ActiveRecord::Base.transaction do
        @store = create_store
        @owner = create_users
        @products = create_catalog
        @customers = create_customers
        create_orders
        create_shipping_cases
        create_delivery_and_whatsapp
        create_shifts
        create_expenses
        create_advertising
      end
      @store
    end

    private

    attr_reader :now, :rng

    # Removes the old demo workspace in an order the foreign keys accept (orders and their lines first).
    def wipe!(store)
      return unless store

      ActiveRecord::Base.transaction do
        store.orders.destroy_all
        ConfirmationShift.where(store_id: store.id).delete_all
        campaign_ids = AdvertisingCampaign.joins(:advertising_account).where(advertising_accounts: { store_id: store.id }).pluck(:id)
        AdvertisingPerformance.where(advertising_campaign_id: campaign_ids).delete_all
        AdvertisingCampaign.where(id: campaign_ids).delete_all
        AdvertisingAccount.where(store_id: store.id).delete_all
        store.destroy!
      end
    end

    def pick(list) = list[rng.rand(list.size)]

    def weighted(list, weights)
      roll = rng.rand(weights.sum)
      list.each_with_index { |item, index| return item if (roll -= weights[index]).negative? }
      list.last
    end

    def create_store
      Store.create!(
        name: "Atlas Beauté", slug: SLUG, currency: "MAD", tagline: "Cosmétiques naturels du Maroc", phone: "0600000000", email: "contact@atlas-beaute.invalid",
        plan: "professional", billing_status: "active", subscription_required: false, storefront_enabled: false, admin_theme: "seallo",
        shipping_cents: 3500, free_shipping_threshold_cents: 40_000, low_stock_threshold: 8, website_url: nil
      )
    end

    def create_users
      owner = @store.users.create!(email: OWNER_EMAIL, name: "Yassine Atlas", password: SecureRandom.base64(24), admin: true, confirmation_role: "supervisor")
      @agents = AGENT_EMAILS.zip([ "Sara Bennani", "Youssef El Fassi", "Hind Tazi" ], [ 500, 600, 500 ]).map do |email, name, pay|
        @store.users.create!(email: email, name: name, password: SecureRandom.base64(24), admin: false, confirmation_role: "agent", pay_per_delivery_cents: pay, return_penalty_cents: 200)
      end
      owner
    end

    def create_catalog
      collection = @store.collections.create!(name: "Soins du visage", slug: "soins-du-visage", subtitle: "Les essentiels", published: true, position: 1)
      body = @store.collections.create!(name: "Corps et hammam", slug: "corps-et-hammam", subtitle: "Rituels beldi", published: true, position: 2)
      CATALOG.each_with_index.map do |(name, short, price, cost, variants, image), index|
        product = @store.products.create!(
          name: name, slug: name.parameterize, status: "active", price_cents: price * 100, cost_cents: cost * 100, currency: "MAD", short_description: short,
          sku: format("ATL-%03d", index + 1), stock: 40 + rng.rand(160), track_inventory: true, featured: index < 3, position: index,
          image_url: "/demo/#{image}.svg", detail_image_url: "/demo/#{image}.svg"
        )
        variants.each_with_index do |(variant_name, variant_price), variant_index|
          product.product_variants.create!(name: variant_name, sku: "#{product.sku}-#{variant_index + 1}", option1_name: "Option", option1_value: variant_name, price_cents: (variant_price || price) * 100,
                                           stock: 20 + rng.rand(80), active: true)
        end
        (index < 4 || index == 5 ? collection : body).collection_products.create!(product: product)
        product
      end
    end

    def create_customers
      70.times.map do |index|
        city, = pick(PLACES)
        name = "#{FIRST_NAMES[index % FIRST_NAMES.size]} #{LAST_NAMES[(index * 5 + index / 7) % LAST_NAMES.size]}"
        @store.customers.create!(name: name, phone: format("0600000%03d", index + 1), city: city, email: ("#{name.parameterize}@exemple.invalid" if (index % 3).zero?))
      end
    end

    # Status by age of the order: the newest are still being confirmed, the oldest are mostly delivered.
    def status_for(age_days)
      if age_days < 1 then weighted(%w[new confirmed preparing cancelled], [ 40, 25, 20, 15 ])
      elsif age_days < 2.5 then weighted(%w[confirmed preparing awaiting_pickup in_transit out_for_delivery delivered cancelled unreachable], [ 6, 8, 12, 26, 22, 14, 8, 4 ])
      elsif age_days < 5 then weighted(%w[in_transit out_for_delivery delivered unreachable postponed returned address_issue cancelled], [ 6, 10, 58, 5, 4, 8, 2, 7 ])
      else weighted(%w[delivered returned cancelled], [ 72, 15, 13 ])
      end
    end

    def create_orders
      shipped_statuses = %w[awaiting_pickup picked_up in_transit out_for_delivery unreachable postponed delivered returned]
      ORDER_COUNT.times do |index|
        age = (DAYS * (rng.rand**1.25)).floor # a few more orders recently
        created = (now - age.days).change(hour: 8 + rng.rand(14), min: rng.rand(60))
        created = [ created, now - rng.rand(5..90).minutes ].min
        status = status_for((now - created) / 1.day)
        customer = pick(@customers)
        place = PLACES.find { |c, *| c == customer.city } || pick(PLACES)
        lines = (rng.rand < 0.25 ? 2 : 1).times.map do
          product = weighted(@products, [ 6, 5, 4, 3, 3, 2, 3, 2 ])
          variant = product.product_variants.to_a.sample(random: rng)
          quantity = rng.rand < 0.12 ? 2 : 1
          price = variant&.price_cents || product.price_cents
          { product: product, variant: variant, quantity: quantity, price: price }
        end
        subtotal = lines.sum { |line| line[:price] * line[:quantity] }
        shipping = subtotal >= 40_000 ? 0 : 3500
        total = subtotal + shipping
        shipped = shipped_statuses.include?(status)
        at = ->(offset, cap = 1.minute) { [ created + offset, now - cap ].min }
        fee = pick(DELIVERY_FEES)
        delivered_at = at.call(rng.rand(2..4).days + rng.rand(0..20).hours) if status == "delivered"
        paid = status == "delivered" && age_of(created) > 6 && rng.rand < 0.8
        order = @store.orders.create!(
          customer: customer, number: format("ATL%d-%05d", DATA_VERSION, 2000 + index), status: status, payment_method: "cod", subtotal_cents: subtotal, shipping_cents: shipping, total_cents: total, currency: "MAD",
          customer_name: customer.name, customer_phone: customer.phone, customer_city: customer.city, customer_district: place[1], customer_address: place[2],
          notes: (pick([ "Appeler avant de livrer", "Livrer après 17 h", "Laisser chez le gardien" ]) if rng.rand < 0.12), tags: ([ "instagram", "tiktok" ].sample(random: rng) if rng.rand < 0.5),
          confirmed_at: (at.call(rng.rand(10..240).minutes) unless status.in?(%w[new cancelled])), shipped_at: (at.call(1.day + rng.rand(0..8).hours) if shipped),
          delivered_at: delivered_at, cancelled_at: (at.call(rng.rand(30..600).minutes) if status == "cancelled"), cancel_reason: ("Le client a changé d'avis" if status == "cancelled"),
          returned_at: (at.call(rng.rand(4..8).days) if status == "returned"),
          sendit_code: (format("SD%07d", 4_200_000 + index) if shipped), sendit_status: (status.upcase if shipped), delivery_provider: ("sendit" if shipped), sendit_fee: (fee / 100.0 if shipped),
          delivery_fee_cents: (fee if status == "delivered"), return_fee_cents: (pick([ 1500, 1500, 2000 ]) if status == "returned"),
          sendit_return_status: (age_of(created) > 9 && status == "returned" ? "RETURN_SELLER" : ("RETURN_WAREHOUSE" if status == "returned")),
          sendit_synced_at: (at.call(rng.rand(1..40).hours) if shipped),
          collected_cents: (total if paid), collected_at: ([ delivered_at + 2.days, now - 1.hour ].min if paid),
          created_at: created, updated_at: [ created + 1.hour, now ].min
        )
        lines.each do |line|
          order.order_items.create!(product: line[:product], product_variant: line[:variant], product_name: line[:product].name, variant_name: line[:variant]&.display_name, quantity: line[:quantity],
                                    unit_price_cents: line[:price], total_cents: line[:price] * line[:quantity], unit_cost_cents: line[:product].cost_cents)
        end
        add_confirmation(order, status, created)
      end
      @customers.each { |customer| customer.update_columns(orders_count: @store.orders.where(customer_id: customer.id).count) }
    end

    # Confirmed orders that the "Envoyer les colis confirmés" page must catch: duplicates, customers who cancelled before, a blocked number, an incomplete address.
    def create_shipping_cases
      @case_index = 0
      serum, argan, creme, coffret = @products.values_at(0, 1, 2, 5)
      # Two duplicate pairs: same number, same products, a few hours apart.
      [ [ "Salma Alaoui", "Casablanca", serum ], [ "Reda Benjelloun", "Marrakech", argan ] ].each do |name, city, product|
        customer = special_customer(name, city)
        special_order(customer, product, status: "confirmed", hours_ago: 6)
        special_order(customer, product, status: "confirmed", hours_ago: 3)
      end
      # Customers who already cancelled an older order, now with a new confirmed one.
      [ [ "Imane Tazi", "Rabat", creme, 35 ], [ "Hamza Kettani", "Tanger", coffret, 70 ], [ "Nora Skalli", "Fès", serum, 120 ] ].each do |name, city, product, days|
        customer = special_customer(name, city)
        special_order(customer, product, status: "cancelled", hours_ago: days * 24)
        special_order(customer, argan, status: "cancelled", hours_ago: (days + 20) * 24) if days > 60
        special_order(customer, product, status: "confirmed", hours_ago: 2)
      end
      # A blocked number and an incomplete address.
      blocked = special_customer("Karim Zniber", "Agadir")
      BlockedPhone.create!(store: @store, phone_key: BlockedPhone.key_for(blocked.phone), reason: "Refus répétés de colis", blocked_by: @owner)
      special_order(blocked, creme, status: "confirmed", hours_ago: 4)
      special_order(special_customer("Zineb Naciri", "Oujda"), serum, status: "confirmed", hours_ago: 5, address: "—")
      # A few clean ones, ready to go.
      [ [ "Ayoub Haddad", "Salé", argan ], [ "Lina Chraibi", "Kénitra", coffret ], [ "Othmane Lahlou", "Meknès", creme ], [ "Asmae Berrada", "Tétouan", serum ] ].each do |name, city, product|
        special_order(special_customer(name, city), product, status: "confirmed", hours_ago: rng.rand(1..8))
      end
    end

    def special_customer(name, city)
      @case_index += 1
      @store.customers.create!(name: name, phone: format("0600000%03d", 900 + @case_index), city: city)
    end

    def special_order(customer, product, status:, hours_ago:, address: nil)
      created = now - hours_ago.hours
      place = PLACES.find { |c, *| c == customer.city } || PLACES.first
      price = product.price_cents
      order = @store.orders.create!(
        customer: customer, number: format("ATL%d-%05d", DATA_VERSION, 9000 + @store.orders.count), status: status, payment_method: "cod", subtotal_cents: price, shipping_cents: 3500, total_cents: price + 3500, currency: "MAD",
        customer_name: customer.name, customer_phone: customer.phone, customer_city: customer.city, customer_district: place[1], customer_address: address || place[2],
        confirmed_at: (created + 20.minutes unless status == "cancelled"), cancelled_at: (created + 1.hour if status == "cancelled"), cancel_reason: ("Le client a changé d'avis" if status == "cancelled"),
        created_at: created, updated_at: created + 1.hour
      )
      order.order_items.create!(product: product, product_name: product.name, quantity: 1, unit_price_cents: price, total_cents: price, unit_cost_cents: product.cost_cents)
      add_confirmation(order, status, created) unless OrderConfirmation.exists?(order_id: order.id) # a blocked number gets its own confirmation on creation
      customer.update_columns(orders_count: @store.orders.where(customer_id: customer.id).count)
      order
    end

    def age_of(time) = (now - time) / 1.day

    def add_confirmation(order, status, created)
      agent = pick(@agents)
      if status == "new"
        callback = rng.rand < 0.3
        order.create_order_confirmation!(store: @store, disposition: callback ? "callback" : "pending", callback_at: (now + rng.rand(10..120).minutes if callback), attributed_user: agent, attributed_at: created)
        return
      end
      outcome = status == "cancelled" ? "cancelled" : "confirmed"
      disposition = outcome
      confirmation = order.create_order_confirmation!(store: @store, disposition: disposition, assigned_user: agent, attributed_user: agent, attributed_at: created, claimed_at: created + 5.minutes)
      rng.rand(0..1).times do
        confirmation.confirmation_attempts.create!(store: @store, user: agent, actor_label: agent.name, outcome: "no_answer", handled_seconds: rng.rand(40..120), call_seconds: rng.rand(5..30), created_at: created + 8.minutes)
      end
      confirmation.confirmation_attempts.create!(store: @store, user: agent, actor_label: agent.name, outcome: outcome, handled_seconds: rng.rand(90..260), call_seconds: rng.rand(60..200), created_at: created + rng.rand(12..90).minutes)
    end

    def create_delivery_and_whatsapp
      @store.delivery_accounts.create!(provider: "sendit", name: "Sendit (Atlas Beauté)", code: "ATLAS01", contact_name: "Atlas Beauté", contact_phone: "0600000000", account_type: "normal", pickup_city: "Casablanca",
                                       delivery_fee: 35, return_fee: 15, is_active: true, connected_at: now - 40.days, cities_count: 500, cities_synced_at: now - 1.day)
      account = WhatsappAccount.new(store: @store, name: "Atlas Beauté", display_phone: "+212 600 000 000", phone_number_id: "100000000000001", business_account_id: "100000000000002", read_receipts: true,
                                    auto_send_new_orders: false, new_order_message: "Bonjour {name}, merci pour votre commande {number} chez Atlas Beauté. Nous vous appellerons pour la confirmer.")
      account.access_token = "demo-token-not-real"
      account.save!
      @store.orders.where(status: %w[confirmed preparing awaiting_pickup in_transit delivered]).order(created_at: :desc).limit(25).each do |order|
        @store.whatsapp_messages.create!(whatsapp_account: account, order: order, kind: "new_order", to_phone: order.customer_phone, body: "Bonjour #{order.customer_name.split.first}, merci pour votre commande #{order.number}.",
                                         status: "sent", sent_at: order.created_at + 2.minutes, created_at: order.created_at + 2.minutes)
      end
    end

    # Hours of the agents: a working day for each of the last two weeks, ended (never left open).
    def create_shifts
      @agents.each_with_index do |agent, index|
        14.times do |days_ago|
          day = (now - days_ago.days).beginning_of_day
          next if day.wday == 0
          started = day + (9 + index % 2).hours + rng.rand(0..25).minutes
          ended = started + (7 + rng.rand(0..2)).hours + rng.rand(0..40).minutes
          next if started > now - 10.minutes
          ended = [ ended, now - 5.minutes ].min
          ConfirmationShift.create!(store: @store, user: agent, started_at: started, ended_at: ended, last_seen_at: ended, end_reason: "manual")
        end
      end
    end

    def create_expenses
      3.times do |month|
        base = (now - month.months).beginning_of_month.to_date
        { "packaging" => [ 420_00, "Cartons et rembourrage" ], "staff" => [ 1_800_00, "Préparation des colis" ], "rent" => [ 2_500_00, "Local de stockage" ], "software" => [ 150_00, "Outils et abonnements" ],
          "tools" => [ 260_00, "Imprimante d'étiquettes" ] }.each do |category, (amount, note)|
          @store.store_expenses.create!(spent_on: base + rng.rand(0..24), category: category, amount_cents: amount + rng.rand(0..40) * 100, note: note)
        end
      end
    end

    def create_advertising
      account = AdvertisingAccount.create!(store: @store, name: "Atlas Beauté — Meta", provider: "Meta", active: true)
      [ [ "Sérum Vitamine C — Prospection", 0.9 ], [ "Huile d'argan — Reciblage", 0.5 ], [ "Coffret Soin — Cadeaux", 0.7 ] ].each do |name, scale|
        campaign = account.advertising_campaigns.create!(name: name, active: true)
        45.times do |offset|
          spend = ((350 + rng.rand(0..250)) * scale * 100).round
          orders = (spend / 100.0 / (55 + rng.rand(0..40))).ceil
          campaign.advertising_performances.create!(date: now.to_date - offset, spend_cents: spend, delivered_revenue_cents: (orders * 0.62 * 21_000).round, fulfillment_cost_cents: (orders * 0.62 * 3_800).round,
                                                    confirmed_orders: orders, delivered_orders: (orders * 0.62).round, clicks: 80 + rng.rand(0..160), impressions: 3_000 + rng.rand(0..4_000))
        end
      end
    end
  end
end
