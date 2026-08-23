import { Controller } from "@hotwired/stimulus"

// Receiving end of the artifact-side hook. Phase 1 only proves the channel is
// live; the comment overlay is built on these messages in phase 2.
export default class extends Controller {
  static targets = ["frame"]

  connect() {
    this.onMessage = this.onMessage.bind(this)
    window.addEventListener("message", this.onMessage)
  }

  disconnect() { window.removeEventListener("message", this.onMessage) }

  onMessage(event) {
    // Every artifact has its own origin, so identity comes from the frame, not event.origin.
    if (!this.hasFrameTarget || event.source !== this.frameTarget.contentWindow) return
    const data = event.data
    if (!data || typeof data.type !== "string" || !data.type.startsWith("artifacto:")) return
    console.debug("[artifacto]", data)
  }

  copy() { navigator.clipboard.writeText(window.location.href) }
}
