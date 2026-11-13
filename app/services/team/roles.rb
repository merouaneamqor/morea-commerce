module Team
  # The roles of a workspace and what each one can open, for the team page (Rôles and Permissions d'applications tabs). The roles are fixed (system roles): the owner
  # (every account that is an admin) and the confirmation agent. The texts are French, translated by the page.
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
      [ "subscription", "Abonnement et plan", %i[owner] ]
    ].freeze

    ALL = [
      Role.new(key: :owner, name: "Propriétaire", description: "Accès complet à la boutique : commandes, centre d'appels, règles d'attribution, facturation des agents, WhatsApp, boutique et équipe.", areas: AREAS.select { |_, _, roles| roles.include?(:owner) }.map(&:first)),
      Role.new(key: :agent, name: "Agent de confirmation", description: "Son propre tableau de bord, sa file d'attente selon les règles d'attribution, la création de commandes, son pointage et sa facturation.", areas: AREAS.select { |_, _, roles| roles.include?(:agent) }.map(&:first))
    ].freeze

    module_function

    def for_user(user) = user.admin? ? :owner : :agent

    def find(key) = ALL.find { |role| role.key == key }
  end
end
