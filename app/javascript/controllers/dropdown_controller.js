import { Controller } from "@hotwired/stimulus"

// Generic click-to-open / click-outside-to-close dropdown.
// Usage:
//   <div data-controller="dropdown">
//     <button data-action="dropdown#toggle">Open</button>
//     <div data-dropdown-target="menu" hidden>…</div>
//   </div>
export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this._outside = this.closeFromOutside.bind(this)
    this._escape = this.closeFromEscape.bind(this)
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
    document.addEventListener("click", this._outside, true)
    document.addEventListener("keydown", this._escape, true)
  }

  close() {
    if (!this.open) return
    this.menuTarget.hidden = true
    this.element.dataset.open = "false"
    document.removeEventListener("click", this._outside, true)
    document.removeEventListener("keydown", this._escape, true)
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
