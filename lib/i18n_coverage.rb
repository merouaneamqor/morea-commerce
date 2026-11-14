# Compares the translations of every locale with French, the reference: which keys are missing, which have a different set of %{placeholders},
# which are still a copy of the French text. Used by spec/i18n_coverage_spec.rb and, to see what is left to translate, from the console:
#   bin/rails runner 'puts I18nCoverage.report(:es)'
module I18nCoverage
  REFERENCE = :fr

  module_function

  # Only the texts of config/locales: the ones the gems bring (rails-i18n, devise...) are complete or incomplete on their own.
  def app_translations
    @app_translations ||= begin
      backend = I18n::Backend::Simple.new
      backend.load_translations(Dir[Rails.root.join("config/locales/**/*.{yml,rb}")])
      backend.send(:translations)
    end
  end

  def locales = app_translations.keys

  # { "dotted.key" => value } for every leaf of the locale (arrays such as day names are leaves).
  def flat(locale)
    tree = app_translations[locale.to_sym] || {}
    {}.tap do |out|
      walk = lambda do |node, path|
        if node.is_a?(Hash) then node.each { |key, value| walk.call(value, path + [ key.to_s ]) }
        else out[path.join(".")] = node
        end
      end
      walk.call(tree, [])
    end
  end

  def missing(locale) = flat(REFERENCE).keys - flat(locale).keys

  def extra(locale) = flat(locale).keys - flat(REFERENCE).keys

  # Keys whose %{placeholders} differ from French: the text would crash or print the wrong thing.
  def placeholder_mismatches(locale)
    reference = flat(REFERENCE)
    flat(locale).filter_map do |key, value|
      next unless value.is_a?(String) && reference[key].is_a?(String)

      # "one"/"zero"/"two" forms may spell the number in words (Arabic "يوم واحد"), so %{count} can be absent there.
      ignored = key.match?(/\.(zero|one|two)\z/) ? [ "count" ] : []
      key if (placeholders(value) - ignored) != (placeholders(reference[key]) - ignored)
    end
  end

  # Long texts that are identical to the French ones: probably not translated yet (brand names and codes are short and ignored).
  def copies_of_french(locale)
    reference = flat(REFERENCE)
    flat(locale).filter_map { |key, value| key if value.is_a?(String) && value.length > 24 && reference[key] == value }
  end

  def placeholders(text) = text.scan(/%\{(\w+)\}/).flatten.sort

  def report(locale)
    lines = [ "#{locale}: #{flat(locale).size} keys (#{REFERENCE}: #{flat(REFERENCE).size})" ]
    { "missing" => missing(locale), "different placeholders" => placeholder_mismatches(locale), "copies of the French text" => copies_of_french(locale) }.each do |label, keys|
      lines << "#{label}: #{keys.size}"
      lines.concat(keys.first(40).map { |key| "  #{key}" })
    end
    lines.join("\n")
  end
end
