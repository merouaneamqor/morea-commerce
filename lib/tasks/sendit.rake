namespace :morea do
  namespace :sendit do
    desc "Push confirmed orders missing a Sendit parcel and refresh parcels in progress"
    task sync: :environment do
      abort "Set SENDIT_PUBLIC_KEY and SENDIT_SECRET_KEY first." unless Sendit::Client.configured?

      to_push, to_refresh = Sendit::Sync.pending_orders
      (to_push.to_a + to_refresh.to_a).each do |order|
        action = order.sendit_code.present? ? :refresh! : :push!
        Sendit::Sync.new(order).public_send(action)
        order.reload
        puts "#{order.number} #{action.to_s.delete("!").ljust(7)} #{order.sendit_code || "-"} #{order.sendit_status || "-"} #{order.status}#{" ERROR: #{order.sendit_error}" if order.sendit_error}"
      end
    end
  end
end
