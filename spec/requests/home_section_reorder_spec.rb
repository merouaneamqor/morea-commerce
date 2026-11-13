require "rails_helper"

RSpec.describe "Admin home section drag-and-drop ordering", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) do
    Store.create!(slug: "section-order-#{SecureRandom.hex(5)}", name: "Section order workspace",
      currency: "MAD", storefront_enabled: true)
  end
  let(:staff) do
    store.users.create!(email: "section-order-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
  end

  def sign_in
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: staff.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def sections
    @sections ||= [ "hero", "ticker", "rich_text" ].each_with_index.map do |kind, position|
      store.home_sections.create!(kind: kind, position: position, visible: true)
    end
  end

  def reorder(ids)
    patch "/admin/home_sections/reorder", params: { ordered_ids: ids }
  end

  it "persists a complete tenant-scoped drag-and-drop order" do
    first, second, third = sections
    sign_in

    reorder([ third.id, first.id, second.id ])

    expect(response).to have_http_status(:no_content)
    expect(store.home_sections.ordered.pluck(:id)).to eq([ third.id, first.id, second.id ])
    expect(store.home_sections.ordered.pluck(:position)).to eq([ 0, 1, 2 ])
  end

  it "rejects missing section IDs without partially changing positions" do
    first, second, third = sections
    sign_in

    reorder([ third.id, first.id ])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq("error" => "The section order is invalid.")
    expect(store.home_sections.ordered.pluck(:id)).to eq([ first.id, second.id, third.id ])
  end

  it "rejects duplicate section IDs without partially changing positions" do
    first, second, third = sections
    sign_in

    reorder([ third.id, first.id, first.id ])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(store.home_sections.ordered.pluck(:id)).to eq([ first.id, second.id, third.id ])
  end

  it "rejects an ID from another workspace without changing either workspace" do
    first, second, third = sections
    foreign = Store.create!(slug: "foreign-section-#{SecureRandom.hex(5)}", name: "Foreign section workspace",
      currency: "MAD", storefront_enabled: true)
    foreign_section = foreign.home_sections.create!(kind: "hero", position: 0, visible: true)
    sign_in

    reorder([ third.id, second.id, foreign_section.id ])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(store.home_sections.ordered.pluck(:id)).to eq([ first.id, second.id, third.id ])
    expect(foreign_section.reload.position).to eq(0)
  end
end
