# frozen_string_literal: true

class AgentChangeset < ApplicationRecord
  STATUSES = %w[previewed applied verified rolled_back failed].freeze

  belongs_to :store

  validates :token, presence: true, uniqueness: { scope: :store_id }
  validates :status, inclusion: { in: STATUSES }
  validates :max_level, inclusion: { in: 1..3 }

  before_validation :ensure_token, on: :create

  def previewed?
    status == "previewed"
  end

  def applied?
    status == "applied" || status == "verified"
  end

  def rolled_back?
    status == "rolled_back"
  end

  private

  def ensure_token
    self.token = "cs_#{SecureRandom.urlsafe_base64(12)}" if token.blank?
  end
end
