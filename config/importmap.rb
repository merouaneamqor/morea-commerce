# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# Loaded when a page actually uses the controller. Preloading every file
# competes with the hero and product images.
pin_all_from "app/javascript/controllers", under: "controllers", preload: false

# Chart.js 4.5.1, vendored with its color dependency for same-origin loading.
pin "chart.js/auto", to: "chartjs-auto.js", preload: false

pin "admin_pwa", preload: false
