# frozen_string_literal: true

# Copy and price labels for the seallo sign-in, sign-up, plan and payment pages.
# Strings are written in French (as on seallo) and translated through the same dictionary.
module SealloAuthHelper
  SEALLO_DICTIONARY = JSON.parse(Rails.root.join("config/seallo_auth_dictionary.json").read).freeze

  def st(french)
    return french if I18n.locale == :fr

    texts = SEALLO_DICTIONARY[french]
    return french unless texts

    # Each entry is [English, Arabic, Spanish].
    texts[{ en: 0, ar: 1, es: 2 }.fetch(I18n.locale, 0)] || french
  end

  def plan_amount(number)
    number_with_delimiter(number, delimiter: " ")
  end

  def plan_orders_label(plan)
    plan["orders"].nil? ? st("Commandes illimitées") : "#{plan_amount(plan["orders"])} #{st("commandes/mois")}"
  end

  def plan_stores_label(plan)
    plan["stores"].nil? ? st("Boutiques illimitées") : "#{plan["stores"]} #{st(plan["stores"] > 1 ? "boutiques" : "boutique")}"
  end

  # Strings the plans page script needs, in the visitor's language.
  def plans_page_strings
    [
      "/ mois", "/ an", "Facturé", "Sans carte, sans engagement", "Offre de lancement", "Le plus populaire",
      "Tous les outils, illimités", "jours d'essai gratuit", "Un instant…", "Plan choisi", "Plan actuel", "Commencer",
      "Choisir", "Commandes illimitées", "commandes/mois", "Boutiques illimitées", "boutiques", "boutique", "Gratuit"
    ].index_with { |key| st(key) }
  end
end
