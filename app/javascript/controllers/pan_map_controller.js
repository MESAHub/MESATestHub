import { Controller } from "@hotwired/stimulus"

// Two-state pan for the subway-map window (newest-on-left layout).
//
// The track has two resting positions per page:
//   shift = 0 (maxShift)        → "newest" view (stations 0..12).
//   shift = -(track_w - win_w)  → "oldest" view (stations 12..24).
//
// Clicking an arrow either animates between the two views or
// follows the older/newer page URL if we're already at that side's
// far end. Each button also flips a `data-mode` attribute between
// `pan` and `paginate` and shows/hides its "Newer" / "Older" text
// label so the user can see at a glance what the next click will
// do.
export default class extends Controller {
  static targets = ["track", "olderButton", "newerButton", "olderLabel", "newerLabel"]
  static values = {
    shift: Number,
    minShift: Number,
    maxShift: Number,
    olderUrl: String,
    newerUrl: String
  }

  connect() {
    this.refreshButtons()
  }

  // Older = further back in time = toward the RIGHT in this layout.
  // Animating to oldest view means the track translates further
  // left (more negative shift).
  panOlder(event) {
    event.preventDefault()
    if (this.canPanOlder) {
      this.shiftValue = this.minShiftValue
      this.applyShift()
    } else if (this.olderUrlValue) {
      window.location.href = this.olderUrlValue
    }
  }

  // Newer = closer to head = toward the LEFT in this layout. Animate
  // back to shift=0.
  panNewer(event) {
    event.preventDefault()
    if (this.canPanNewer) {
      this.shiftValue = this.maxShiftValue
      this.applyShift()
    } else if (this.newerUrlValue) {
      window.location.href = this.newerUrlValue
    }
  }

  applyShift() {
    this.trackTarget.style.transform = `translateX(${this.shiftValue}px)`
    this.refreshButtons()
  }

  refreshButtons() {
    const olderMode = this.canPanOlder ? "pan" : "paginate"
    const newerMode = this.canPanNewer ? "pan" : "paginate"
    this.setMode(this.olderButtonTargets[0], this.olderLabelTargets[0], olderMode, !!this.olderUrlValue)
    this.setMode(this.newerButtonTargets[0], this.newerLabelTargets[0], newerMode, !!this.newerUrlValue)
  }

  setMode(button, label, mode, hasUrl) {
    if (!button) return
    button.dataset.mode = mode
    if (label) {
      // Show the label only when this button's next click would
      // actually navigate to a different page.
      const showLabel = mode === "paginate" && hasUrl
      label.classList.toggle("hidden", !showLabel)
    }
    // Dim + disable when the click would do nothing.
    const disabled = mode === "paginate" && !hasUrl
    button.classList.toggle("opacity-30", disabled)
    button.classList.toggle("pointer-events-none", disabled)
    if (disabled) {
      button.setAttribute("aria-disabled", "true")
    } else {
      button.removeAttribute("aria-disabled")
    }
  }

  get canPanOlder() {
    return this.shiftValue > this.minShiftValue
  }

  get canPanNewer() {
    return this.shiftValue < this.maxShiftValue
  }
}
