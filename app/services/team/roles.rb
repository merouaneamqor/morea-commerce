module Team
  # The roles that exist in seallo and what each one can open, for the team page (Rôles and Permissions d'applications tabs). They are fixed (system roles): the super
  # administrator of the platform, the owner (every account that is an admin) and the confirmation agent. The texts are French, translated by the page.
  module Roles
    Role = Data.define(:key, :name, :description, :areas)

    # [key, label, which roles have it]
    AREAS = [
      [ "dashboard", "Tableau de bord", %i[owner agent] ],
      [ "orders", "Commandes", %i[owner agent] ],
      [ "create_orders", "Créer des commandes", %i[owner agent] ],
      [ "queue", "Centre d'appels : file d'attente", %i[owner agent] ],
      [ "analytics", "Analyses du centre d'appels", %i[owner agent] ],
      [ "clock_in", "Pointage", %i[owner agent] ],
      [ "own_billing", "Sa facturation", %i[agent] ],
      [ "assignments", "Attributions et règles d'attribution", %i[owner] ],
      [ "attendance", "Pointages de l'équipe", %i[owner] ],
      [ "agent_billing", "Facturation des agents", %i[owner] ],
      [ "customers", "Clients", %i[owner] ],
      [ "delivery", "Livraison", %i[owner] ],
      [ "products", "Produits", %i[owner] ],
      [ "accounting", "Comptabilité", %i[owner] ],
      [ "team", "Équipe", %i[owner] ],
      [ "integrations", "Intégrations API", %i[owner] ],
      [ "whatsapp", "WhatsApp", %i[owner] ],
      [ "store", "Boutique (logo, adresse du site)", %i[owner] ],
      [ "subscription", "Abonnement et plan", %i[owner] ],
      [ "platform", "Administration de la plateforme", %i[super_admin] ]
    ].freeze

    ALL = [
      Role.new(key: :super_admin, name: "Super administrateur", description: "Accès à toute la plateforme : toutes les boutiques, les utilisateurs, les abonnements et l'administration de seallo.", areas: AREAS.map(&:first)),
      Role.new(key: :owner, name: "Propriétaire", description: "Accès complet à la boutique : commandes, centre d'appels, règles d'attribution, facturation des agents, WhatsApp, boutique et équipe.", areas: AREAS.select { |_, _, roles| roles.include?(:owner) }.map(&:first)),
      Role.new(key: :agent, name: "Agent de confirmation", description: "Son propre tableau de bord, sa file d'attente selon les règles d'attribution, la création de commandes, son pointage et sa facturation.", areas: AREAS.select { |_, _, roles| roles.include?(:agent) }.map(&:first))
    ].freeze

    # The applications the permissions screen shows: [key, label, the areas it holds].
    GROUPS = [
      [ "dashboard", "Tableau de bord", %w[dashboard] ],
      [ "orders", "Commandes", %w[orders create_orders] ],
      [ "call_center", "Centre d'appels", %w[queue analytics clock_in assignments attendance agent_billing own_billing] ],
      [ "customers", "Clients", %w[customers] ],
      [ "delivery", "Livraison", %w[delivery] ],
      [ "products", "Produits", %w[products] ],
      [ "accounting", "Comptabilité", %w[accounting] ],
      [ "team", "Équipe", %w[team] ],
      [ "integrations", "Intégrations API", %w[integrations] ],
      [ "whatsapp", "WhatsApp", %w[whatsapp] ],
      [ "store", "Boutique et abonnement", %w[store subscription] ]
    ].freeze

    # Which area a page belongs to: the controller, and for two controllers the action. A controller that is not listed is open to everyone who can sign in.
    CONTROLLER_AREAS = {
      "admin/dashboard" => "dashboard", "admin/my_stats" => "dashboard",
      "admin/customers" => "customers", "admin/delivery" => "delivery", "admin/delivery_accounts" => "delivery",
      "admin/products" => "products", "admin/variants" => "products", "admin/inventory" => "products", "admin/collections" => "products", "admin/discounts" => "products", "admin/media" => "products",
      "admin/accounting" => "accounting", "admin/users" => "team",
      "admin/store_connections" => "integrations", "admin/seallo_connections" => "integrations", "admin/woocommerce_connections" => "integrations", "admin/agent_api" => "integrations",
      "admin/meta_ads" => "integrations", "admin/advertising" => "integrations", "admin/pixels" => "integrations",
      "admin/whatsapp" => "whatsapp", "admin/stores" => "store", "admin/subscriptions" => "subscription",
      "admin/agent_billing" => "agent_billing", "admin/my_billing" => "own_billing", "admin/assignment_rules" => "assignments"
    }.freeze
    ORDER_CREATION_ACTIONS = %w[new create product_search quick_product].freeze
    CONFIRMATION_ACTIONS = { "analytics" => "analytics", "dashboard" => "analytics", "assignments" => "assignments", "assign" => "assignments", "auto_assign" => "assignments",
                             "attendance" => "attendance", "clock_in" => "clock_in", "clock_out" => "clock_in", "heartbeat" => "clock_in" }.freeze

    module_function

    def area_for(controller_path, action)
      case controller_path
      when "admin/orders" then ORDER_CREATION_ACTIONS.include?(action.to_s) ? "create_orders" : "orders"
      when "admin/confirmations" then CONFIRMATION_ACTIONS.fetch(action.to_s, "queue")
      else CONTROLLER_AREAS[controller_path]
      end
    end

    def areas_of(user) = find(for_user(user)).areas

    def for_user(user) = user.super_admin? ? :super_admin : (user.admin? ? :owner : :agent)

    def find(key) = ALL.find { |role| role.key == key }
  end
end
