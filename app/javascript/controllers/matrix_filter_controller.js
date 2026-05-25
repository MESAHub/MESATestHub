import { Controller } from "@hotwired/stimulus"

// Filters for the merged Summary matrix's row list. Three orthogonal
// axes that AND together — a row is visible only if it passes all
// three:
//
//   1. Chip filter (single-select tag from the toolbar).
//   2. Module filter (single-select from a dropdown next to chips).
//   3. Free-text search across the test name.
//
// Each row wrapper carries:
//   data-matrix-filter-target="row"
//   data-categories="failing checksums fpe pending"
//   data-module="star"
//   data-test-name="rsp_gyre"
//
// The row wrapper itself is a `display: contents` div, so toggling
// its `hidden` removes the wrapped grid items from layout cleanly.
export default class extends Controller {
  static targets = ["row", "chip", "empty", "moduleButton", "moduleItem", "moduleLabel", "search"]
  static values = {
    active: { type: String, default: "all" },
    module: { type: String, default: "all" },
    query: { type: String, default: "" }
  }

  connect() {
    this.apply()
    // Banner shortcuts ("See mixed tests", "See failing tests")
    // route through the tabs controller, which broadcasts a
    // `tabs:request` event with `detail.params` carrying any URL
    // params other than `tab` itself. Pick the `filter` one off so
    // landing on Summary from a shortcut lands on the right chip.
    this._onTabsRequest = this._handleTabsRequest.bind(this)
    document.addEventListener("tabs:request", this._onTabsRequest)
  }

  disconnect() {
    document.removeEventListener("tabs:request", this._onTabsRequest)
  }

  _handleTabsRequest(event) {
    if (!event.detail || event.detail.tab !== "summary") return
    const filter = event.detail.params && event.detail.params.filter
    if (!filter) return
    this.activeValue = filter
    this.apply()
  }

  select(event) {
    const filter = event.currentTarget.dataset.filter
    if (!filter || filter === this.activeValue) return
    this.activeValue = filter
    this.apply()
  }

  selectModule(event) {
    event.preventDefault()
    const mod = event.currentTarget.dataset.module
    if (!mod) return
    this.moduleValue = mod
    if (this.hasModuleLabelTarget) {
      this.moduleLabelTarget.textContent = mod === "all" ? "All modules" : mod
    }
    this.moduleItemTargets.forEach((item) => {
      item.setAttribute("aria-selected", item.dataset.module === mod ? "true" : "false")
    })
    // Close the dropdown the moment a module is picked.
    const dropdownEl = this.element.querySelector('[data-controller~="dropdown"]')
    if (dropdownEl && dropdownEl.dataset.open === "true") {
      const trigger = dropdownEl.querySelector('[data-action*="dropdown#toggle"]')
      trigger && trigger.click()
    }
    this.apply()
  }

  search(event) {
    this.queryValue = (event.currentTarget.value || "").trim().toLowerCase()
    this.apply()
  }

  apply() {
    const filter = this.activeValue
    const mod = this.moduleValue
    const q = this.queryValue
    let visible = 0
    this.rowTargets.forEach((row) => {
      const cats = (row.dataset.categories || "").split(/\s+/).filter(Boolean)
      const rowMod = row.dataset.module || ""
      const name = row.dataset.testName || ""
      const matchesChip = filter === "all" || cats.includes(filter)
      const matchesMod = mod === "all" || rowMod === mod
      const matchesQuery = !q || name.includes(q)
      const show = matchesChip && matchesMod && matchesQuery
      row.hidden = !show
      if (show) visible++
    })
    this._syncChips(filter)
    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = visible > 0
      if (visible === 0) {
        const bits = []
        if (filter !== "all") bits.push(`category “${filter}”`)
        if (mod !== "all") bits.push(`module ${mod}`)
        if (q) bits.push(`matching “${q}”`)
        this.emptyTarget.textContent = bits.length
          ? `No tests in ${bits.join(", ")}.`
          : "No tests match the current filters."
      }
    }
  }

  _syncChips(filter) {
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
  }
}
