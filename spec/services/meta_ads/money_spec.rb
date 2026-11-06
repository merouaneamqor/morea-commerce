# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetaAds::Money do
  it "divides standard currencies by 100 and leaves zero-decimal currencies intact" do
    expect(described_class.from_minor("5000", currency: "EUR")).to eq(BigDecimal("50"))
    expect(described_class.from_minor("5000", currency: "MAD")).to eq(BigDecimal("50"))
    expect(described_class.from_minor("5000", currency: "JPY")).to eq(BigDecimal("5000"))
  end

  it "returns nil for blank or negative values" do
    expect(described_class.from_minor(nil, currency: "EUR")).to be_nil
    expect(described_class.from_minor("", currency: "EUR")).to be_nil
    expect(described_class.from_minor("-1", currency: "EUR")).to be_nil
  end
end
