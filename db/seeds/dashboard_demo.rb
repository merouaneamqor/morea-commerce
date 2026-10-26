# frozen_string_literal: true

abort "Dashboard demo seeds are disabled in production" if Rails.env.production?

store = Store.find_by!(slug: "morea")
now = Time.current.in_time_zone(Admin::OverviewMetrics::ZONE)
demo_prefix = "DEMO-"
order_count = Integer(ENV.fetch("DEMO_ORDER_COUNT", "150"), 10)
abort "DEMO_ORDER_COUNT must be between 1 and 1,000" unless order_count.between?(1, 1_000)

# Replace only this side-effect-free synthetic snapshot. The seed never runs
# transitions, jobs, inventory adjustments, or provider calls.
store.orders.where("number LIKE ?", "#{demo_prefix}%").destroy_all

first_names = %w[Amina Sara Meryem Imane Nora Salma Lina Yasmine Ghita Hanae Ikram Kawtar Zineb Asmae]
last_names = [ "El Idrissi", "Bennani", "Alaoui", "Amrani", "Lahlou", "Berrada", "Tazi", "Chraibi", "El Fassi", "Naciri" ]
locations = [
  [ "Casablanca", "Maarif", "12 rue des Fleurs" ],
  [ "Rabat", "Agdal", "8 avenue Atlas" ],
  [ "Marrakech", "Hivernage", "24 rue Ibn Sina" ],
  [ "Tangier", "Malabata", "6 boulevard Pasteur" ],
  [ "Agadir", "Talborjt", "19 avenue Hassan II" ],
  [ "Fes", "Ville Nouvelle", "31 rue Lalla Aicha" ],
  [ "Meknes", "Hamria", "15 avenue des FAR" ],
  [ "Kenitra", "Maamora", "9 rue Sebou" ],
  [ "Tetouan", "Centre", "18 avenue Mohammed V" ],
  [ "Oujda", "Al Qods", "22 boulevard Allal El Fassi" ]
].freeze

customers = 40.times.map do |index|
  city, district, address = locations[index % locations.length]
  name = "#{first_names[index % first_names.length]} #{last_names[(index * 3) % last_names.length]}"
  phone = format("06%08d", 10_000 + index)
  customer = store.customers.find_or_initialize_by(phone: phone)
  customer.assign_attributes(name: name, city: city)
  customer.save!
  [ customer, district, address ]
end

products = store.products.active.includes(:product_variants).order(:position, :id).to_a
abort "Seed the Morea catalog before loading dashboard demo data" if products.empty?

status_cycle = %w[
  delivered delivered delivered delivered delivered delivered delivered delivered
  cancelled cancelled new new confirmed confirmed preparing awaiting_pickup
  in_transit out_for_delivery unreachable returned
].freeze
shipped_statuses = %w[awaiting_pickup picked_up in_transit out_for_delivery unreachable postponed delivered returned].freeze

created_orders = order_count.times.map do |index|
  customer, district, address = customers[index % customers.length]
  status = status_cycle[index % status_cycle.length]
  days_ago = index % 30
  created_at = (now.to_date - days_ago.days).in_time_zone(Admin::OverviewMetrics::ZONE)
    .change(hour: 8 + ((index * 7) % 13), min: (index * 11) % 60)
  created_at = [ created_at, now - 5.minutes ].min

  line_count = index % 5 == 0 ? 2 : 1
  lines = line_count.times.map do |line_index|
    product = products[(index + line_index * 3) % products.length]
    variants = product.product_variants.select(&:active?)
    variant = variants[(index + line_index) % variants.length] if variants.any?
    quantity = index % 13 == 0 && line_index.zero? ? 2 : 1
    unit_price = variant&.unit_price_cents || product.price_cents
    { product: product, variant: variant, quantity: quantity, unit_price: unit_price,
      total: unit_price * quantity }
  end
  subtotal = lines.sum { |line| line.fetch(:total) }
  discount = index % 10 == 0 ? (subtotal * 0.1).round : 0
  shipping = subtotal >= 80_000 ? 0 : 3_500
  courier_order = shipped_statuses.include?(status)
  lifecycle_time = ->(offset, before_now) { [ created_at + offset, now - before_now ].min }

  order = store.orders.create!(
    customer: customer,
    number: format("%s%s-%03d", demo_prefix, now.strftime("%Y%m"), index + 1),
    status: status,
    payment_method: "cod",
    subtotal_cents: subtotal,
    discount_cents: discount,
    discount_code: ("WELCOME10" if discount.positive?),
    shipping_cents: shipping,
    total_cents: subtotal - discount + shipping,
    currency: "MAD",
    customer_name: customer.name,
    customer_phone: customer.phone,
    customer_city: customer.city,
    customer_district: district,
    customer_address: address,
    notes: "Synthetic local demo order",
    tags: [ ("repeat" if index % 7 == 0), ("instagram" if index.even?) ].compact.join(", ").presence,
    confirmed_at: (lifecycle_time.call(2.hours, 4.minutes) unless status.in?(%w[new cancelled])),
    shipped_at: (lifecycle_time.call(1.day, 3.minutes) if courier_order),
    delivered_at: (lifecycle_time.call(3.days, 2.minutes) if status == "delivered"),
    cancelled_at: (lifecycle_time.call(4.hours, 2.minutes) if status == "cancelled"),
    returned_at: (lifecycle_time.call(6.days, 1.minute) if status == "returned"),
    cancel_reason: ("Customer changed their mind" if status == "cancelled"),
    sendit_code: (format("DEMO-SENDIT-%05d", index + 1) if courier_order),
    sendit_status: (status.upcase if courier_order),
    sendit_fee: (35.0 if courier_order),
    sendit_synced_at: (lifecycle_time.call(1.day + 30.minutes, 30.seconds) if courier_order),
    created_at: created_at,
    updated_at: created_at
  )

  lines.each do |line|
    order.order_items.create!(
      product: line.fetch(:product),
      product_variant: line[:variant],
      product_name: line.fetch(:product).name,
      variant_name: line[:variant]&.display_name,
      quantity: line.fetch(:quantity),
      unit_price_cents: line.fetch(:unit_price),
      total_cents: line.fetch(:total)
    )
  end

  if status == "new"
    disposition = index.even? ? "pending" : "callback"
    order.create_order_confirmation!(store: store, disposition: disposition,
      callback_at: (now - 30.minutes if disposition == "callback"))
  end
  order
end

account = AdvertisingAccount.find_or_create_by!(store: store, name: "Dashboard Demo", provider: "Meta")
campaigns = [ "Essential Set — Prospecting", "Morea Retargeting" ].map do |name|
  account.advertising_campaigns.find_or_create_by!(name: name)
end

campaigns.each_with_index do |campaign, campaign_index|
  30.times do |offset|
    performance = campaign.advertising_performances.find_or_initialize_by(date: now.to_date - offset.days)
    performance.assign_attributes(
      spend_cents: 3_500 + campaign_index * 1_200 + offset * 75,
      delivered_revenue_cents: 12_500 + campaign_index * 4_000 + offset * 250,
      fulfillment_cost_cents: 2_100 + campaign_index * 500 + offset * 45,
      confirmed_orders: 4 + campaign_index,
      delivered_orders: 3 + campaign_index,
      clicks: 75 + offset * 4,
      impressions: 2_400 + offset * 125
    )
    performance.save!
  end
end

customers.each do |customer, _district, _address|
  customer.update_column(:orders_count, store.orders.where(customer_id: customer.id).count)
end

variant_lines = OrderItem.joins(:order).where(orders: { id: created_orders.map(&:id) }).where.not(product_variant_id: nil).count
puts "Local demo: #{created_orders.count} orders across 30 days, #{customers.count} customers, #{variant_lines} variant order lines, #{campaigns.count} campaigns"
