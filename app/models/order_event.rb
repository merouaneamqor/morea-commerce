# frozen_string_literal: true

class OrderEvent < ApplicationRecord
  KINDS = %w[comment created edited duplicated archived unarchived status].freeze

  belongs_to :order
  belongs_to :user, optional: true

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :body, presence: true, if: -> { kind == "comment" }

  scope :recent, -> { order(created_at: :desc) }
end
