require "rails_helper"
require "nokogiri"

RSpec.describe "Confirmation queue contact alerts", type: :request do
  let(:password) { "Synthetic-contact-password-123!" }
  let(:store) { Store.create!(slug: "contact-queue-#{SecureRandom.hex(5)}", name: "Synthetic contact queue", currency: "MAD") }
  let(:manager) do
    store.users.create!(email: "manager-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
  end
  let(:agent) do
    store.users.create!(email: "agent-#{SecureRandom.hex(5)}@example.test", password: password,
      admin: false, confirmation_role: "agent")
  end
  let!(:order) do
    store.orders.create!(customer_name: "Synthetic buyer", customer_phone: nil, customer_city: "Casablanca",
      customer_address: "Synthetic address", currency: "MAD", import_contact_issues: [ "phone" ])
  end

  it "shows managers and on-shift agents the pending order with an alert and disabled call controls" do
    ConfirmationShift.create!(store: store, user: agent, started_at: 1.hour.ago)
    [ manager, agent ].each do |user|
      browser = ActionDispatch::Integration::Session.new(Rails.application)
      browser.host! "#{store.slug}.#{Store.base_domain}"
      browser.post "/admin/login", params: { email: user.email, password: password, locale: "en" }
      expect(browser.response).to have_http_status(:redirect)

      browser.get "/admin/confirmations", params: { locale: "en" }
      expect(browser.response).to have_http_status(:ok)
      document = Nokogiri::HTML(browser.response.body)
      # Phone cards come first in the DOM; the desktop table still carries the same controls.
      containers = document.css("a[href='/admin/orders/#{order.id}']").filter_map { |link|
        link.ancestors("tr, li.admin-mobile-list__card").first
      }.uniq
      expect(containers.size).to eq(2)
      containers.each do |row|
        expect(row.at_css("[data-import-contact-alert][role='alert']").text).to include("Phone number")
        expect(row.at_css("form[action='/admin/confirmations/#{order.id}/call'] button[disabled]")).to be_present
        expect(row.at_css("form[action='/admin/confirmations/#{order.id}/claim']")).to be_nil
        expect(row.at_css("a[href^='tel:']")).to be_nil
      end
      expect(document.css("[data-import-contact-form]")).to be_empty
      expect(browser.response.body).not_to match(/translation missing|translation_missing/i)
    end
  end
end
