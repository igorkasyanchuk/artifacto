# Pin npm packages by running ./bin/importmap

pin "application"
pin "artifact"
# preload: false — the wrapper page loads its own entry point and must not pull
# Turbo at all; the other pages import it and can pay for one extra request.
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: false
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
