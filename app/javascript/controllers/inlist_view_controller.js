import { Controller } from "@hotwired/stimulus"

// Inlist switch on the test-on-commit page. The server renders the
// usual all-inlists instances table plus one table per inlist; this
// shows exactly one of them. "all" is the normal totals table.
export default class extends Controller {
  static targets = ["button", "panel"]
  static values = { selected: { type: String, default: "all" } }

  connect() {
    this.apply()
  }

  select(event) {
    this.selectedValue = event.currentTarget.dataset.inlist
    this.apply()
  }

  apply() {
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.inlist !== this.selectedValue
    })
    this.buttonTargets.forEach((button) => {
      const on = button.dataset.inlist === this.selectedValue
      button.setAttribute("aria-pressed", on.toString())
      button.classList.toggle("bg-brand-soft", on)
      button.classList.toggle("text-brand-soft-text", on)
      button.classList.toggle("text-fg-muted", !on)
    })
  }
}
