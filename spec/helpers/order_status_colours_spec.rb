require "rails_helper"

# The same status has the same colour everywhere: waiting gold, scheduled blue, confirmed green, in progress purple, delivered green,
# cancelled and returned red. These are the dashboard's latest-orders badges and the admin badges.
RSpec.describe "Order status colours", type: :helper do
  describe "the dashboard badges" do
    {
      "new" => [ "Nouvelle", "bg-[#fdf0d9]" ], "confirmed" => [ "Confirmée", "bg-[#e3f3e8]" ], "postponed" => [ "Reportée", "bg-[#e1edfb]" ],
      "cancelled" => [ "Annulée", "bg-[#fbe7ea]" ], "shipped" => [ "En cours", "bg-[#eee8fb]" ], "delivered" => [ "Livrée", "bg-[#e3f3e8]" ], "returned" => [ "Retournée", "bg-[#fbe7ea]" ]
    }.each do |status, (label, background)|
      it "paints #{status} as #{label} on #{background}" do
        text, classes = helper.seller_status_badge(status)

        expect(text).to eq(label)
        expect(classes).to include(background)
      end
    end

    it "paints a confirmed order green, never blue, and a cancelled one red" do
      expect(helper.seller_status_badge("confirmed").last).to include("text-[#2f7a4a]")
      expect(helper.seller_status_badge("cancelled").last).to include("text-[#b4344e]")
    end

    it "paints the finer Sendit statuses like the status they stand for" do
      expect(helper.seller_status_badge("out_for_delivery")).to eq(helper.seller_status_badge("shipped"))
      expect(helper.seller_status_badge("preparing")).to eq(helper.seller_status_badge("confirmed"))
    end
  end

  describe "the admin badges" do
    it "paints confirmed green and cancelled red" do
      expect(helper.admin_badge("confirmed")).to include("admin-badge--success")
      expect(helper.admin_badge("cancelled")).to include("admin-badge--critical")
      expect(helper.admin_badge("delivered")).to include("admin-badge--success")
      expect(helper.admin_badge("returned")).to include("admin-badge--critical")
      expect(helper.admin_badge("new")).to include("admin-badge--attention")
    end
  end
end
