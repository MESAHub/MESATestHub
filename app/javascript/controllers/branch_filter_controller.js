import { Controller } from "@hotwired/stimulus"

// Type-to-filter for the branch picker dropdown. There are dozens of
// branches (EbF/* and friends), so scrolling alone is painful.
//
// Each option carries `data-search-key` (lowercased branch name) and
// sits inside a `section` target together with its section label; a
// section hides when none of its rows match, and the `empty` target
// shows when nothing matches at all.
//
// Keys: Enter follows the first visible match, ArrowDown/ArrowUp walk
// the visible rows (ArrowUp from the first row returns to the field),
// and Escape clears a non-empty field (the dropdown controller leaves
// the menu open for that one; an empty field's Escape closes it).
export default class extends Controller {
  static targets = ["menu", "search", "row", "section", "empty"]

  // Wired to `dropdown:opened`. The menu hangs off the chip's left
  // edge, which on a phone sits mid-line, so nudge it left until it
  // fits inside the viewport (16px gutter). Measures against <body>,
  // not innerWidth: an overflowing menu has already widened the
  // layout viewport by the time this runs.
  position() {
    this.menuTarget.style.left = ""
    const overflow = this.menuTarget.getBoundingClientRect().right - (document.body.clientWidth - 16)
    if (overflow > 0) this.menuTarget.style.left = `${-overflow}px`
  }

  filter() {
    const q = this.searchTarget.value.trim().toLowerCase()
    this.rowTargets.forEach((row) => {
      row.hidden = q !== "" && !(row.dataset.searchKey || "").includes(q)
    })
    this.sectionTargets.forEach((section) => {
      section.hidden = !section.querySelector("[data-branch-filter-target~='row']:not([hidden])")
    })
    this.emptyTarget.hidden = this.visibleRows.length > 0
  }

  // Wired to `dropdown:closed` so the next open starts from the full list.
  reset() {
    if (this.searchTarget.value === "") return
    this.searchTarget.value = ""
    this.filter()
  }

  navigate(event) {
    const rows = this.visibleRows
    const onSearch = event.target === this.searchTarget
    const index = rows.indexOf(event.target)

    switch (event.key) {
      case "Enter":
        if (!onSearch) return
        event.preventDefault()
        if (rows[0]) rows[0].click()
        break
      case "Escape":
        if (!onSearch || this.searchTarget.value === "") return
        event.preventDefault()
        this.reset()
        break
      case "ArrowDown":
        event.preventDefault()
        if (onSearch) rows[0]?.focus()
        else rows[index + 1]?.focus()
        break
      case "ArrowUp":
        event.preventDefault()
        if (index > 0) rows[index - 1].focus()
        else if (index === 0) this.searchTarget.focus()
        break
    }
  }

  get visibleRows() {
    return this.rowTargets.filter((row) => !row.hidden)
  }
}
