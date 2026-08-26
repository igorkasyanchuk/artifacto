// Entry point for the wrapper page only (layouts/artifact).
//
// Deliberately no Turbo: this is the page that frames untrusted HTML, so it runs
// the least JavaScript of anything on the app origin. It also keeps Turbo's
// injected <style> off this page, which the app's `style-src 'self'` refuses.
import "controllers"
