// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

const path = window.location.pathname
if (document.querySelector("[data-seller-shell], [data-admin-pwa]") || path.startsWith("/admin") || path.startsWith("/superadmin")) {
  import("admin_pwa")
}
