# frozen_string_literal: true

require "rails_helper"

RSpec.describe MediaUrl do
  it "asks Cloudinary for auto format and quality when resizing" do
    url = "https://res.cloudinary.com/demo/image/upload/v1/sample.jpg"
    expect(described_class.sized(url, width: 640)).to include("/c_limit,f_auto,q_auto,w_640/")
  end
end
