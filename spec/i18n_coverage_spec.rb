require "rails_helper"
require "i18n_coverage"

# Every text of the platform exists in every language. French is the reference: a key added in French without its English, Spanish and Arabic
# text fails here, and so does a text whose %{placeholders} do not match the French one (it would print "%{name}" or raise).
RSpec.describe "Translation coverage" do
  %i[en es ar].each do |locale|
    describe locale.to_s do
      it "has every key of the French translations" do
        missing = I18nCoverage.missing(locale)

        expect(missing).to be_empty, "#{missing.size} keys missing in #{locale}:\n#{missing.first(40).join("\n")}"
      end

      it "uses the same %{placeholders} as French in every text" do
        wrong = I18nCoverage.placeholder_mismatches(locale)

        expect(wrong).to be_empty, "placeholders differ from French in #{locale}:\n#{wrong.first(40).join("\n")}"
      end
    end
  end

  it "has an English, Arabic and Spanish text for every seller page label" do
    incomplete = SellerHelper::SELLER_LABELS.select { |_french, texts| %w[en ar es].any? { |locale| texts[locale].to_s.strip.empty? } }.keys

    expect(incomplete).to be_empty, "#{incomplete.size} seller labels lack a translation:\n#{incomplete.first(40).join("\n")}"
  end

  it "has no translation of a language the platform does not offer" do
    expect(I18nCoverage.locales.map(&:to_s).sort).to eq(Morea::Locales::AVAILABLE.map(&:to_s).sort)
  end
end
