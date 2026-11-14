# frozen_string_literal: true

require "rails_helper"

RSpec.describe Store, "host resolution" do
  let!(:store) { Store.create!(slug: "host-#{SecureRandom.hex(4)}", name: "Host Store", currency: "MAD") }

  it "recognizes apex and www hosts" do
    domain = Store.base_domain
    expect(Store.apex_host?(domain)).to be(true)
    expect(Store.apex_host?("www.#{domain}")).to be(true)
    expect(Store.apex_host?("#{store.slug}.#{domain}")).to be(false)
  end

  it "finds a tenant by subdomain and ignores reserved or nested hosts" do
    domain = Store.base_domain
    expect(Store.find_by_host("#{store.slug}.#{domain}")).to eq(store)
    expect(Store.find_by_host("#{store.slug}.#{domain}:3010")).to eq(store)
    expect(Store.find_by_host("www.#{domain}")).to be_nil
    expect(Store.find_by_host("admin.#{domain}")).to be_nil
    expect(Store.find_by_host("api.#{domain}")).to be_nil
    expect(Store.find_by_host("app.#{domain}")).to be_nil
    expect(Store.find_by_host("a.b.#{domain}")).to be_nil
    expect(Store.find_by_host("unknown.#{domain}")).to be_nil
    expect(Store.find_by_host("custom.example.com")).to be_nil
  end
end
