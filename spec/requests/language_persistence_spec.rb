require "rails_helper"
require "nokogiri"

RSpec.describe "Language choice is remembered", type: :request do
  def html_lang = Nokogiri::HTML(response.body).at_css("html")["lang"]

  it "offers one language button with every language, and keeps the chosen language on the other pages" do
    host! Store.base_domain
    get "/"
    menu = Nokogiri::HTML(response.body).at_css(".platform-language-menu")
    expect(menu.at_css("button[aria-haspopup=listbox]")).to be_present
    expect(menu.css("a").map { |link| link["hreflang"] }).to eq(%w[fr en es ar])

    get "/", params: { locale: "es" }
    expect(html_lang).to eq("es")

    get "/admin/login"
    expect(html_lang).to eq("es")
    get "/"
    expect(html_lang).to eq("es")

    get "/", params: { locale: "ar" }
    get "/signup"
    expect(html_lang).to eq("ar")
  end
end
