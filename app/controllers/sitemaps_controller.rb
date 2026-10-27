# frozen_string_literal: true

class SitemapsController < ApplicationController
  def show
    @entries = Store.apex_host?(request.host) ? platform_entries : storefront_entries

    respond_to do |format|
      format.xml
    end
  end

  private

  def storefront_entries
    origin = current_store.origin
    collections = current_store.collections.published.select(:slug)
    products = current_store.products.active.select(:slug)
    pages = current_store.pages.published.select(:slug)

    Morea::Locales::AVAILABLE.flat_map do |locale|
      prefix = "/#{locale}"
      entries = [
        "#{origin}#{prefix}",
        "#{origin}#{prefix}/collections"
      ]
      entries.concat(collections.map do |collection|
        "#{origin}#{prefix}/collections/#{collection.slug}"
      end)
      entries.concat(products.map do |product|
        "#{origin}#{prefix}/products/#{product.slug}"
      end)
      entries.concat(pages.map do |page|
        "#{origin}#{prefix}/pages/#{page.slug}"
      end)
      entries
    end
  end

  def platform_entries
    [ "#{Store.platform_origin}/" ]
  end
end
