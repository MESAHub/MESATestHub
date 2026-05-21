import { Controller } from "@hotwired/stimulus"

// Single-select filter for the Tests-tab row list. Each chip carries
// `data-filter="…"`; each row carries `data-categories="failing
// checksums fpe"` (space-separated tags). Clicking a chip hides any
// row whose tags don't include the chip's filter. The `all` chip is
// the no-op default.
//
// Multi-select would be tempting (combine Failing + Checksums) but
// the design's segmented control is single-select, and most filter
// pairs the user would want are already covered by row-level tag
// stacking (a "Checksums" filter shows all rows with a checksum tag,
// including failing-and-checksum rows).
export default class extends Controller {
  static targets = ["row", "chip", "empty"]
  static values = { active: { type: String, default: "all" } }

  connect() {
    this.applyActive(this.activeValue)
  }

  select(event) {
    const filter = event.currentTarget.dataset.filter
    if (!filter || filter === this.activeValue) return
    this.activeValue = filter
    this.applyActive(filter)
  }

  applyActive(filter) {
    let visible = 0
    this.rowTargets.forEach((row) => {
      const cats = (row.dataset.categories || "").split(/\s+/).filter(Boolean)
      const show = filter === "all" || cats.includes(filter)
      row.hidden = !show
      if (show) visible++
    })
    this.chipTargets.forEach((chip) => {
      const on = chip.dataset.filter === filter
      chip.setAttribute("aria-pressed", on ? "true" : "false")
      chip.classList.toggle("border-brand", on)
      chip.classList.toggle("bg-brand-soft", on)
      chip.classList.toggle("text-brand-soft-text", on)
      chip.classList.toggle("border-border", !on)
      chip.classList.toggle("bg-bg-elev", !on)
      chip.classList.toggle("text-fg-muted", !on)
    })
    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = visible > 0
      if (visible === 0 && filter !== "all") {
        this.emptyTarget.textContent = `No tests in the “${filter}” category.`
      }
    }
  }
}
