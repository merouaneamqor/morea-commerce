require "rails_helper"
require "nokogiri"

# The tab icon of the platform's pages is the seallo headset, and the file is served.
RSpec.describe "Favicon", type: :request do
  def icons = Nokogiri::HTML(response.body).css("link[rel='icon'], link[rel='apple-touch-icon']").map { |link| link["href"] }

  it "uses the seallo icon on the platform home page, the sign-in page and the sign-up page" do
    host! Store.base_domain
    [ "/", "/admin/login", "/signup" ].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(icons).to include("/seallo-favicon.png")
    end
  end

  it "has the icon file in public" do
    expect(Rails.public_path.join("seallo-favicon.png")).to exist
    expect(File.binread(Rails.public_path.join("seallo-favicon.png"), 8)).to eq("\x89PNG\r\n\x1A\n".b)
  end
end
