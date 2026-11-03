# frozen_string_literal: true

# Catalogue of delivery companies a merchant can add an account for (config/carriers.yml).
module Carriers
  CATALOG = YAML.safe_load_file(Rails.root.join("config/carriers.yml")).freeze

  module_function

  def regions = CATALOG.fetch("regions")
  def countries = CATALOG.fetch("countries")
  def providers = CATALOG.fetch("providers")
  def provider(key) = providers[key.to_s] || providers.fetch("other")
  def provider?(key) = providers.key?(key.to_s)
end
