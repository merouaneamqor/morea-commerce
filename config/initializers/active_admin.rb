# frozen_string_literal: true

ActiveAdmin.setup do |config|
  config.site_title = "Morea Superadmin"
  config.authentication_method = :authenticate_super_admin!
  config.current_user_method = :current_admin_user
  config.logout_link_path = :admin_logout_path
  config.logout_link_method = :delete
  config.comments = false
  config.clear_javascripts!

  config.default_namespace = :superadmin
  config.namespace :superadmin do |superadmin|
    superadmin.route_options = { path: "superadmin" }
  end
end
