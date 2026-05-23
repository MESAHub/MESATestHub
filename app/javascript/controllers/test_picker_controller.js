import { Controller } from "@hotwired/stimulus"

// Free-text filter for the test-on-commit headline's test picker
// dropdown. The dropdown holds every TCC on the current commit
// (often hundreds), so scrolling alone is unworkable.
//
// Each option carries `data-search-key="<module>/<name>"` (lowercase
// server-side); on every input event we hide rows whose key doesn't
// `includes()` the current query, and reveal an empty-state element
// when nothing matches.
export default class extends Controller {
  static targets = ["search", "row", "empty"]

  connect() {
    this.apply()
  }

  filter() {
    this.apply()
  }

  apply() {
    const q = (this.hasSearchTarget ? this.searchTarget.value : "").trim().toLowerCase()
    let visible = 0
    this.rowTargets.forEach((row) => {
      const key = row.dataset.searchKey || ""
      const show = !q || key.includes(q)
      row.hidden = !show
      if (show) visible++
    })
    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = visible > 0
    }
  }
}
