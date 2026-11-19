# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Morea homepage wordmark", type: :request do
  let(:store) do
    Store.find_or_create_by!(slug: "morea") { |record| record.name = "Morea"; record.currency = "MAD" }
  end

  before do
    store.update!(storefront_enabled: true)
    store.home_sections.destroy_all
    store.home_sections.create!(kind: "hero", visible: true, position: 0,
      heading: "Synthetic campaign", button_label: "View collection", link: "collections",
      image_url: "https://images.example.test/synthetic-hero.jpg")
    host! "#{store.slug}.#{Store.base_domain}"
  end

  it "adds one decorative logo while retaining the hero and collection link in FR, EN and AR" do
    %w[fr en ar].each do |locale|
      get "/#{locale}"
      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      expect(page.css('[data-controller="hero-atmosphere"]').size).to eq(1)
      expect(page.at_css('.campaign-hero__logo')['aria-hidden']).to eq("true")
      expect(page.at_css('.campaign-hero__logo-fallback').text).to eq("Morea")
      expect(page.at_css('.campaign-hero h1').text).to eq("Synthetic campaign")
      expect(page.at_css('.campaign-btn')['href']).to eq("/#{locale}/collections")
      expect(page.css('link[rel="modulepreload"]').map { |node| node['href'] }.join).not_to include("three.")
    end
  end

  it "does not repeat WebGL contexts on later hero sections" do
    store.home_sections.create!(kind: "hero", visible: true, position: 1, heading: "Later campaign",
      image_url: "https://images.example.test/another-hero.jpg")
    get "/fr"
    expect(Nokogiri::HTML(response.body).css('[data-controller="hero-atmosphere"]').size).to eq(1)
  end

  it "leaves other stores with their own ordinary branding" do
    other = Store.create!(slug: "logo-other-#{SecureRandom.hex(4)}", name: "Other Studio", currency: "MAD", storefront_enabled: true)
    other.home_sections.create!(kind: "hero", visible: true, heading: "Other campaign", image_url: "https://images.example.test/other.jpg")
    host! "#{other.slug}.#{Store.base_domain}"
    get "/en"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('data-controller="hero-atmosphere"')
    expect(Nokogiri::HTML(response.body).at_css('.campaign-hero__brand').text).to eq("Other Studio")
  end

  it "keeps the ordinary wordmark for an image-free hero and does not publish a disabled storefront" do
    store.home_sections.first.update!(image_url: nil)
    get "/en"
    expect(response.body).not_to include('data-controller="hero-atmosphere"')
    store.update!(storefront_enabled: false)
    get "/en"
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('data-controller="hero-atmosphere"')
  end
end
