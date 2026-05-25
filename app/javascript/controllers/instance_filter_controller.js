import { Controller } from "@hotwired/stimulus"

// Filters for the test-on-commit instances table. Two axes,
// AND-applied — a row is visible only if both pass:
//
//   1. Status filter (single-select from a segmented control).
//   2. Free-text search across "computer name + checksum",
//      normalized to lowercase by the server.
//
// Each row carries:
//   data-instance-filter-target="row"
//   data-row-status="pass|fail|pending|other"
//   data-row-search="rusty 6bd9a47"
//
// The empty-state element listens via `data-instance-filter-target=
// "empty"` and gets `hidden` toggled when at least one row is
// visible.
export default class extends Controller {
  static targets = ["row", "statusChip", "search", "empty"]
  static values = {
    status: { type: String, default: "all" },
    query: { type: String, default: "" }
  }

  connect() {
    this.apply()
  }

  selectStatus(event) {
    const status = event.currentTarget.dataset.status
    if (!status || status === this.statusValue) return
    this.statusValue = status
    this.apply()
  }

  search(event) {
    this.queryValue = (event.currentTarget.value || "").trim().toLowerCase()
    this.apply()
  }

  apply() {
    const status = this.statusValue
    const q = this.queryValue
    let visible = 0
    this.rowTargets.forEach((row) => {
      const rowStatus = row.dataset.rowStatus || ""
      const blob = row.dataset.rowSearch || ""
      const matchesStatus = status === "all" || rowStatus === status
      const matchesQuery = !q || blob.includes(q)
      const show = matchesStatus && matchesQuery
      row.hidden = !show
      if (show) visible++
    })
    this._syncChips(status)
    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = visible > 0
    }
  }

  _syncChips(status) {
    this.statusChipTargets.forEach((chip) => {
      const on = chip.dataset.status === status
      chip.setAttribute("aria-pressed", on ? "true" : "false")
      chip.classList.toggle("bg-brand-soft", on)
      chip.classList.toggle("text-brand-soft-text", on)
      chip.classList.toggle("text-fg-muted", !on)
    })
  }
}
