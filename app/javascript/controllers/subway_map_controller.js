import { Controller } from "@hotwired/stimulus"

// Hover popover for the subway map.
//
// Each <a> circle has data-commit-id="…" plus mouseenter/mouseleave/
// focus/blur actions. The matching popover (with the same
// data-commit-id) is hidden by default; the controller toggles it on
// hover or keyboard focus.
export default class extends Controller {
  static targets = ["popover"]

  show(event) {
    const id = event.currentTarget.dataset.commitId
    this._setVisibility(id, true)
  }

  hide(event) {
    const id = event.currentTarget.dataset.commitId
    this._setVisibility(id, false)
  }

  _setVisibility(id, visible) {
    const popover = this.popoverTargets.find((p) => p.dataset.commitId === id)
    if (!popover) return
    if (visible) {
      popover.removeAttribute("hidden")
    } else {
      popover.setAttribute("hidden", "")
    }
  }
}
