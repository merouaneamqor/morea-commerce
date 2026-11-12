// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

import "admin_pwa"

// A form inside a Turbo frame that answers with a whole page (for example the new order, redirected to its page) leaves
// the frame and opens that page normally instead of showing "Content missing".
document.addEventListener("turbo:frame-missing", (event) => {
  event.preventDefault()
  event.detail.visit(event.detail.response)
})
