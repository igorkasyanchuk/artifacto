import { Controller } from "@hotwired/stimulus"

// Drag & drop uploader. Talks to the same open API a curl call would.
export default class extends Controller {
  static targets = ["drop", "input", "title", "ttl", "network", "pin", "result", "url", "token", "error"]

  open() { this.inputTarget.click() }
  over(event) { event.preventDefault(); this.dropTarget.classList.add("is-over") }
  leave() { this.dropTarget.classList.remove("is-over") }

  drop(event) {
    event.preventDefault()
    this.leave()
    const file = event.dataTransfer.files[0]
    if (file) this.upload(file)
  }

  picked() {
    const file = this.inputTarget.files[0]
    if (file) this.upload(file)
  }

  async upload(file) {
    this.errorTarget.classList.add("hidden")
    this.dropTarget.textContent = `Uploading ${file.name}…`

    const body = new FormData()
    body.append("file", file)
    body.append("format", file.name.endsWith(".md") ? "markdown" : "html")
    body.append("expires_in_days", this.ttlTarget.value)
    if (this.titleTarget.value) body.append("title", this.titleTarget.value)
    if (this.networkTarget.checked) body.append("allow_network", "true")
    if (this.pinTarget.value) body.append("pin", this.pinTarget.value)

    try {
      const response = await fetch("/api/v1/artifacts", { method: "POST", body })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || `Upload failed (${response.status})`)

      this.urlTarget.textContent = data.url
      this.urlTarget.href = data.url
      this.tokenTarget.textContent = data.edit_token
      this.resultTarget.classList.remove("hidden")
      this.dropTarget.textContent = "Drop another file"
    } catch (error) {
      this.errorTarget.textContent = error.message
      this.errorTarget.classList.remove("hidden")
      this.dropTarget.textContent = "Drop an HTML or Markdown file, or click to pick one"
    }
  }
}
