# frozen_string_literal: true

namespace :morea do
  namespace :billing do
    desc "Mark stores past_due when they have overdue issued invoices"
    task sync_past_due: :environment do
      Store.find_each(&:sync_billing_past_due!)
      puts "Synced billing past_due for #{Store.count} stores"
    end
  end
end
