module Whatsapp
  # The keywords a merchant can put in a message, written {{like_this}}; each is replaced by the order's value. Templates (approved by Meta) will map
  # the same keywords to their variables later.
  module Keywords
    KEYS = %w[nom_client numero_commande total ville adresse boutique produits].freeze
    DEFAULT_MESSAGE = "Bonjour {{nom_client}}, merci pour votre commande {{numero_commande}} chez {{boutique}} ({{total}}). Notre équipe va vous appeler pour la confirmer.".freeze
    PATTERN = /\{\{\s*(\w+)\s*\}\}/

    module_function

    def unknown_in(text) = text.scan(PATTERN).flatten.uniq - KEYS

    def values(order)
      {
        "nom_client" => order.customer_name.to_s,
        "numero_commande" => "##{order.number}",
        "total" => order.total_display,
        "ville" => order.customer_city.to_s,
        "adresse" => order.customer_address.to_s,
        "boutique" => order.store.name.to_s,
        "produits" => order.order_items.map { |item| "#{item.quantity} × #{item.product_name}#{" (#{item.variant_name})" if item.variant_name.present?}" }.join(", ")
      }
    end

    def render(text, order)
      table = values(order)
      text.gsub(PATTERN) { table.fetch(Regexp.last_match(1), "") }
    end
  end
end
