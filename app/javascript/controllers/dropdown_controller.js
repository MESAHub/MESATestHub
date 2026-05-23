import { Controller } from "@hotwired/stimulus"

// Generic click-to-open / click-outside-to-close dropdown.
// Usage:
//   <div data-controller="dropdown">
//     <button data-dropdown-target="trigger" data-action="dropdown#toggle">Open</button>
//     <div data-dropdown-target="menu" hidden>…</div>
//   </div>
// The `trigger` target is optional; when present its `aria-expanded`
// attribute is kept in sync with the menu's open state.
export default class extends Controller {
  static targets = ["menu", "trigger"]

  connect() {
    this._outside = this.closeFromOutside.bind(this)
    this._escape = this.closeFromEscape.bind(this)
    this.syncAria()
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    this.open ? this.close() : this.openMenu()
  }

  openMenu() {
    if (this.open) return
    this.menuTarget.hidden = false
    this.element.dataset.open = "true"
    this.syncAria()
    document.addEventListener("click", this._outside, true)
    document.addEventListener("keydown", this._escape, true)
  }

  close() {
    if (!this.open) return
    this.menuTarget.hidden = true
    this.element.dataset.open = "false"
    this.syncAria()
    document.removeEventListener("click", this._outside, true)
    document.removeEventListener("keydown", this._escape, true)
  }

  syncAria() {
    if (!this.hasTriggerTarget) return
    this.triggerTarget.setAttribute("aria-expanded", this.open ? "true" : "false")
  }

  closeFromOutside(event) {
    if (this.element.contains(event.target)) return
    this.close()
  }

  closeFromEscape(event) {
    if (event.key === "Escape") this.close()
  }

  get open() {
    return this.element.dataset.open === "true"
  }
}
