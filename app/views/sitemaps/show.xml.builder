xml.instruct!
xml.urlset(xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9") do
  @entries.each do |location|
    xml.url do
      xml.loc location
    end
  end
end
