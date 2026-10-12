# frozen_string_literal: true

module Catalog
  module Builders
    class Error < StandardError; end

    SECTION_FIELDS = %i[
      id kind position visible image_url link collection_slug limit image_position translations
    ].freeze

    module_function

    def section_schema
      {
        "kinds" => SectionBlock::KINDS.map { |key, label| { "kind" => key, "label" => label } },
        "textFields" => SectionBlock::TEXT_FIELDS.transform_keys(&:to_s).transform_values { |fields| fields.map(&:to_s).map { |f| f.camelize(:lower) } },
        "settingFields" => SectionBlock::SETTING_FIELDS.transform_keys(&:to_s).transform_values { |fields| fields.map { |f| setting_field_name(f) } },
        "linkFormats" => %w[home collections cart track collection:slug product:slug page:slug https://…],
        "imagePosition" => %w[left right],
        "locales" => Morea::Locales::AVAILABLE.map(&:to_s)
      }
    end

    def home_layout(store)
      persisted = store.home_sections.exists?
      sections = if persisted
        store.home_sections.ordered.includes(:translations)
      else
        OnlineStoreDefaults.new(store).home_sections
      end

      {
        surface: "home",
        using_defaults: !persisted,
        preview_urls: preview_urls(store, path: ""),
        announcement: store.announcement,
        section_schema: section_schema,
        sections: sections.map { |section| present_section(section, store) }
      }
    end

    def reorder_home_sections!(store, ids:)
      reorder!(store.home_sections, ids)
      home_layout(store)
    end

    def set_home_layout!(store, sections:, replace: false)
      raise Error, "sections must be an array" unless sections.is_a?(Array)
      raise Error, "At most 40 home sections" if sections.size > 40

      ActiveRecord::Base.transaction do
        kept = []
        sections.each_with_index do |raw, index|
          attrs = normalize_section_attrs(raw).merge(position: index)
          section = StoreOps.upsert_section!(store, attrs)
          kept << section.id
        end
        store.home_sections.where.not(id: kept).destroy_all if replace
      end
      home_layout(store)
    end

    def landing_pages(store)
      store.pages.landing.includes(:translations, page_sections: :translations).order(:slug).map { |page| present_landing(page, include_sections: false) }
    end

    def landing_page(store, slug:)
      page = store.pages.landing.includes(:translations, page_sections: :translations).find_by(slug: slug)
      raise Error, "Landing page not found: #{slug}" unless page

      present_landing(page, include_sections: true)
    end

    def upsert_landing_page!(store, attrs)
      attrs = attrs.to_h.symbolize_keys
      attrs[:new_slug] ||= attrs[:newSlug] || attrs[:new_slug]
      if attrs[:slug].present?
        page = store.pages.find_by(slug: attrs[:slug])
        raise Error, "Page not found: #{attrs[:slug]}" unless page
        raise Error, "The privacy page cannot become a landing page." if page.slug == "privacy"
      else
        page = store.pages.new(published: true)
      end

      page.template = "landing"
      page.published = attrs[:published] unless attrs[:published].nil?
      page.slug = attrs[:new_slug] if attrs[:new_slug].present?
      Catalog::Translations.assign!(page, attrs[:translations]) if attrs[:translations]
      raise Error, "A new landing page needs a fr title." if page.new_record? && page.title.blank?

      StoreOps.save!(page)
      present_landing(page.reload, include_sections: true)
    end

    def delete_landing_page!(store, slug:, confirm:)
      raise Error, "Set confirm: true to delete." unless confirm

      page = store.pages.landing.find_by(slug: slug)
      raise Error, "Landing page not found: #{slug}" unless page

      page.destroy!
      true
    end

    def upsert_landing_section!(store, page_slug:, attrs:)
      page = store.pages.landing.find_by(slug: page_slug)
      raise Error, "Landing page not found: #{page_slug}" unless page

      section = upsert_page_section!(page, attrs)
      present_section(section, store)
    end

    def delete_landing_section!(store, page_slug:, id:, confirm:)
      raise Error, "Set confirm: true to delete." unless confirm

      page = store.pages.landing.find_by(slug: page_slug)
      raise Error, "Landing page not found: #{page_slug}" unless page

      section = page.page_sections.find_by(id: id)
      raise Error, "Section not found: #{id}" unless section

      section.destroy!
      true
    end

    def reorder_landing_sections!(store, page_slug:, ids:)
      page = store.pages.landing.find_by(slug: page_slug)
      raise Error, "Landing page not found: #{page_slug}" unless page

      reorder!(page.page_sections, ids)
      present_landing(page.reload, include_sections: true)
    end

    def set_landing_layout!(store, page_slug:, sections:, replace: false)
      page = store.pages.landing.find_by(slug: page_slug)
      raise Error, "Landing page not found: #{page_slug}" unless page
      raise Error, "sections must be an array" unless sections.is_a?(Array)
      raise Error, "At most 40 landing sections" if sections.size > 40

      ActiveRecord::Base.transaction do
        kept = []
        sections.each_with_index do |raw, index|
          attrs = normalize_section_attrs(raw).merge(position: index)
          section = upsert_page_section!(page, attrs)
          kept << section.id
        end
        page.page_sections.where.not(id: kept).destroy_all if replace
      end
      present_landing(page.reload, include_sections: true)
    end

    def upsert_page_section!(page, attrs)
      attrs = normalize_section_attrs(attrs)
      if attrs[:id].present?
        section = page.page_sections.find_by(id: attrs[:id])
        raise Error, "Section not found: #{attrs[:id]}" unless section
      else
        kind = attrs[:kind].to_s
        raise Error, "kind must be #{SectionBlock::KINDS.keys.join(", ")}." unless SectionBlock::KINDS.key?(kind)

        section = page.page_sections.new(kind: kind)
      end

      section.visible = attrs[:visible] unless attrs[:visible].nil?
      section.position = attrs[:position] unless attrs[:position].nil?
      section.image_url = attrs[:image_url] unless attrs[:image_url].nil?
      section.link = attrs[:link] if attrs[:link].present?
      section.limit = attrs[:limit] unless attrs[:limit].nil?
      if attrs[:image_position].present?
        raise Error, "imagePosition must be left or right." unless %w[left right].include?(attrs[:image_position])

        section.image_position = attrs[:image_position]
      end
      if attrs[:collection_slug].present?
        collection = page.store.collections.find_by(slug: attrs[:collection_slug])
        raise Error, "Collection not found: #{attrs[:collection_slug]}" unless collection

        section.collection_id = collection.id
      end
      Catalog::Translations.assign!(section, attrs[:translations]) if attrs[:translations]
      StoreOps.save!(section)
    end

    def present_landing(page, include_sections:)
      payload = {
        slug: page.slug,
        template: page.template,
        published: page.published,
        preview_urls: preview_urls(page.store, path: "/pages/#{page.slug}"),
        translations: page.translations.sort_by(&:locale).map { |t|
          {
            locale: t.locale,
            title: t.title,
            body: t.body,
            seo_title: t.seo_title,
            seo_description: t.seo_description
          }
        },
        section_count: page.page_sections.size
      }
      if include_sections
        payload[:section_schema] = section_schema
        payload[:sections] = page.page_sections.ordered.includes(:translations).map { |section| present_section(section, page.store) }
      end
      payload
    end

    def present_section(section, store)
      {
        id: section.persisted? ? section.id.to_s : nil,
        kind: section.kind,
        label: section.label,
        position: section.position,
        visible: section.visible,
        image_url: section.image_url.presence,
        image_src: section.image_src,
        link: section.link,
        collection_slug: store.collections.find_by(id: section.collection_id)&.slug,
        limit: section.limit.presence&.to_i,
        image_position: section.image_position,
        translations: section.translations.sort_by(&:locale).map { |t|
          {
            locale: t.locale,
            heading: t.heading,
            subheading: t.subheading,
            body: t.body,
            button_label: t.button_label
          }
        }
      }
    end

    def preview_urls(store, path:)
      Morea::Locales::AVAILABLE.map do |locale|
        {
          locale: locale.to_s,
          url: "#{store.origin}/#{locale}#{path}"
        }
      end
    end

    def reorder!(scope, ids)
      wanted = Array(ids).map(&:to_s)
      raise Error, "ids must not be empty" if wanted.empty?

      records = scope.where(id: wanted).index_by { |record| record.id.to_s }
      missing = wanted - records.keys
      raise Error, "Unknown section ids: #{missing.join(", ")}" if missing.any?

      ActiveRecord::Base.transaction do
        wanted.each_with_index do |id, index|
          records[id].update_column(:position, index)
        end
      end
      true
    end

    def normalize_section_attrs(raw)
      attrs = raw.to_h
      stringified = attrs.deep_stringify_keys
      symbolized = attrs.respond_to?(:symbolize_keys) ? attrs.symbolize_keys : stringified.symbolize_keys
      {
        id: stringified["id"] || symbolized[:id],
        kind: stringified["kind"] || symbolized[:kind],
        visible: if stringified.key?("visible")
                   stringified["visible"]
                 elsif symbolized.key?(:visible)
                   symbolized[:visible]
                 end,
        position: stringified["position"] || symbolized[:position],
        image_url: pick(stringified, symbolized, "imageUrl", "image_url", :image_url),
        link: stringified["link"] || symbolized[:link],
        collection_slug: pick(stringified, symbolized, "collectionSlug", "collection_slug", :collection_slug),
        limit: stringified["limit"] || symbolized[:limit],
        image_position: pick(stringified, symbolized, "imagePosition", "image_position", :image_position),
        translations: stringified["translations"] || symbolized[:translations]
      }
    end

    def pick(stringified, symbolized, *keys)
      keys.each do |key|
        if key.is_a?(Symbol)
          return symbolized[key] if symbolized.key?(key)
        elsif stringified.key?(key)
          return stringified[key]
        end
      end
      nil
    end

    def setting_field_name(field)
      case field
      when :collection_id then "collectionSlug"
      when :image_url then "imageUrl"
      when :image_position then "imagePosition"
      else field.to_s.camelize(:lower)
      end
    end
  end
end
