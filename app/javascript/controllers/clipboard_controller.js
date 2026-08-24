import { Controller } from "@hotwired/stimulus"

// Copies the text of a target element. The wrapper page copies window.location
// instead, which is why that one is not reused here.
export default class extends Controller {
  static targets = ["source", "button"]

  async copy() {
    await navigator.clipboard.writeText(this.sourceTarget.textContent.trim())

    const button = this.hasButtonTarget ? this.buttonTarget : null
    if (!button) return

    const original = button.textContent
    button.textContent = "Copied"
    setTimeout(() => { button.textContent = original }, 1500)
  }
}
