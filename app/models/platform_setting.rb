# frozen_string_literal: true

# One row of platform-wide switches. Super admins edit it from Feature flags.
class PlatformSetting < ApplicationRecord
  HOME_FLAGS = %w[home_maintenance home_coming_soon].freeze

  validates :singleton, uniqueness: true, inclusion: { in: [ true ] }

  def self.current
    find_by(singleton: true) || create!(singleton: true)
  rescue ActiveRecord::RecordNotUnique
    find_by!(singleton: true)
  end

  # What visitors of the public home page see. Maintenance wins when both flags are on.
  def home_page
    return "maintenance" if home_maintenance?
    return "coming_soon" if home_coming_soon?

    "live"
  end

  def home_page_label
    { "maintenance" => "Under maintenance", "coming_soon" => "Coming soon" }.fetch(home_page, "Live home page")
  end
end
