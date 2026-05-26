import { Controller } from "@hotwired/stimulus"

// Writes `data-copy-button-text-value` to the clipboard and flashes
// the label to "Copied" for 1.5s. Falls back gracefully if the
// Clipboard API isn't available (e.g., insecure context) — leaves
// the label unchanged so the button doesn't lie.
export default class extends Controller {
  static targets = ["label"]
  static values = { text: String }

  async copy(event) {
    event.preventDefault()
    if (!navigator.clipboard) return
    try {
      await navigator.clipboard.writeText(this.textValue)
    } catch (_e) {
      return
    }
    const label = this.hasLabelTarget ? this.labelTarget : null
    if (!label) return
    const original = label.textContent
    label.textContent = "Copied"
    clearTimeout(this._restore)
    this._restore = setTimeout(() => { label.textContent = original }, 1500)
  }
}
