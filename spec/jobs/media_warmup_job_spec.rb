# frozen_string_literal: true

require "rails_helper"

RSpec.describe MediaWarmupJob do
  let(:blob) { instance_double(ActiveStorage::Blob, id: 123, url: "https://synthetic.example.test/image") }
  let(:response) { instance_double(Net::HTTPResponse, code: "200") }
  let(:url) { "https://synthetic.example.test/transformed-image" }

  before do
    allow(ActiveStorage::Blob).to receive(:find_by).with(id: blob.id).and_return(blob)
    allow(MediaUrl).to receive(:cloudinary?).with(blob).and_return(true)
    allow(MediaUrl).to receive(:edits).with(blob).and_return({})
    allow(MediaUrl).to receive(:transformation).with({}, store: nil).and_return({})
    allow(MediaUrl).to receive(:sized).with("https://synthetic.example.test/image", width: 960).and_return(url)
    allow(Net::HTTP).to receive(:get_response).with(URI(url)) do |_uri, &block|
      raise "Image must be streamed" unless block

      block.call(response)
      response
    end
  end

  it "performs a GET and discards every image chunk without asking for a buffered body" do
    consumed = 0
    expect(response).not_to receive(:body)
    expect(response).to receive(:read_body) do |&block|
      100.times do
        consumed += 1
        block.call("image chunk")
      end
    end

    described_class.perform_now(blob.id)

    expect(consumed).to eq(100)
  end

  it "keeps retrying a pending 423 transformation" do
    allow(response).to receive(:code).and_return("423")
    allow(response).to receive(:read_body).and_yield("pending")

    travel_to(Time.zone.local(2026, 11, 18, 12)) do
      expect { described_class.perform_now(blob.id) }.to have_enqueued_job(described_class).with(blob.id)
      expect(enqueued_jobs.last[:at]).to be_between(10.seconds.from_now.to_f, 12.seconds.from_now.to_f)
    end
  end

  it "does not fetch deleted or non-Cloudinary blobs" do
    expect(Net::HTTP).not_to receive(:get_response)
    allow(ActiveStorage::Blob).to receive(:find_by).with(id: 999).and_return(nil)
    described_class.perform_now(999)
    allow(MediaUrl).to receive(:cloudinary?).with(blob).and_return(false)
    described_class.perform_now(blob.id)
  end
end
