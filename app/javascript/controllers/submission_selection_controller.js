import { Controller } from "@hotwired/stimulus"

// Drives the per-row checkboxes + selection bar + confirmation
// modal on computers#show. Visible-row selection only — picking a
// "select all matching filter" affordance uses the separate
// `selectAllMatching` target which posts a `select_all_matching=1`
// param to the destroy endpoint and lets the server re-apply the
// active filter scope, rather than trying to enumerate IDs the
// client can't see.
//
// Targets:
//   row          — table rows for each visible submission
//   checkbox     — per-row checkbox (one per row)
//   allCheckbox  — the "select all on this page" header checkbox
//   selectionBar — sticky bar that appears when any row is checked
//   count        — element(s) whose textContent is the selected
//                  count (in the bar AND in the modal title /
//                  confirm button — multiple targets allowed)
//   modal        — <dialog> for the confirmation prompt
//   idsContainer — empty <div> inside the modal's delete form;
//                  populated with hidden inputs on open
//   matchingCount   — element showing total matching the filter
//                     (only shown when count > visible)
//   allMatchingMode — the "delete all N matching" mode toggle. When
//                     enabled, the confirm form gets a hidden
//                     `select_all_matching=1` input instead of the
//                     per-row IDs.
export default class extends Controller {
  static targets = [
    "row", "checkbox", "allCheckbox", "selectionBar", "count",
    "modal", "idsContainer", "modalSummary", "allMatchingToggle"
  ]
  static values = { totalMatching: Number, visibleCount: Number }

  connect() {
    this.allMatchingMode = false
    this.refresh()
  }

  // Per-row checkbox change.
  toggle() {
    this.allMatchingMode = false
    this.refresh()
  }

  // "Select all on this page" header checkbox change.
  toggleAll(event) {
    const checked = event.currentTarget.checked
    this.checkboxTargets.forEach(cb => { cb.checked = checked })
    this.allMatchingMode = false
    this.refresh()
  }

  // "Select all N matching filter" link in the selection bar.
  // Doesn't actually tick anything in the DOM — we set a flag and
  // pass `select_all_matching=1` through the modal form so the
  // server re-derives the set from the filter scope.
  selectAllMatching(event) {
    event.preventDefault()
    this.checkboxTargets.forEach(cb => { cb.checked = true })
    this.allMatchingMode = true
    this.refresh()
  }

  clear(event) {
    if (event) event.preventDefault()
    this.checkboxTargets.forEach(cb => { cb.checked = false })
    this.allMatchingMode = false
    this.refresh()
  }

  refresh() {
    const selected = this.checkboxTargets.filter(cb => cb.checked)
    const visible = selected.length
    const total = this.allMatchingMode
      ? this.totalMatchingValue
      : visible

    if (visible > 0) {
      this.selectionBarTarget.hidden = false
    } else {
      this.selectionBarTarget.hidden = true
    }

    if (this.hasCountTarget) {
      this.countTargets.forEach(el => { el.textContent = total })
    }

    if (this.hasAllCheckboxTarget) {
      const visibleTotal = this.checkboxTargets.length
      this.allCheckboxTarget.checked = visible === visibleTotal && visibleTotal > 0
      this.allCheckboxTarget.indeterminate = visible > 0 && visible < visibleTotal
    }

    if (this.hasAllMatchingToggleTarget) {
      // Show the "select all N matching" hint only when:
      //   - the filter actually matches more than what's on screen, and
      //   - the user has selected every visible row (i.e. they've
      //     clearly opted into bulk selection)
      const shouldShow =
        this.totalMatchingValue > this.visibleCountValue &&
        visible === this.checkboxTargets.length &&
        !this.allMatchingMode
      this.allMatchingToggleTarget.hidden = !shouldShow
    }

    if (this.hasModalSummaryTarget) {
      this.modalSummaryTarget.textContent = this.allMatchingMode
        ? `${total} submissions matching the current filter`
        : `${total} selected submission${total === 1 ? "" : "s"}`
    }
  }

  openConfirm(event) {
    event.preventDefault()
    const visibleSelected = this.checkboxTargets.filter(cb => cb.checked)
    if (visibleSelected.length === 0) return

    // Clear any inputs left over from a previous open.
    this.idsContainerTarget.innerHTML = ""

    if (this.allMatchingMode) {
      const allFlag = document.createElement("input")
      allFlag.type = "hidden"
      allFlag.name = "select_all_matching"
      allFlag.value = "1"
      this.idsContainerTarget.appendChild(allFlag)
    } else {
      visibleSelected.forEach(cb => {
        const input = document.createElement("input")
        input.type = "hidden"
        input.name = "submission_ids[]"
        input.value = cb.value
        this.idsContainerTarget.appendChild(input)
      })
    }

    this.modalTarget.showModal()
  }

  closeConfirm(event) {
    if (event) event.preventDefault()
    this.modalTarget.close()
  }

  // Close when the user clicks the dialog backdrop (the dark area
  // around the modal panel). The browser's default <dialog> behavior
  // is to ignore backdrop clicks; users expect them to dismiss.
  backdropClose(event) {
    if (event.target === this.modalTarget) {
      this.modalTarget.close()
    }
  }
}
