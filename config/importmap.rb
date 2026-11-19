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

# Three.js r180, loaded only by the Morea homepage logo.
pin "three", to: "three.module.min.js", preload: false
pin "three/core", to: "three.core.min.js", preload: false
pin "three/addons/geometries/TextGeometry.js", to: "three-TextGeometry.js", preload: false
pin "three/addons/loaders/FontLoader.js", to: "three-FontLoader.js", preload: false
pin "morea-typeface", to: "morea-typeface.js", preload: false
