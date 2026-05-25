import { Controller } from "@hotwired/stimulus"

// Calendar dropdown for the commits-index date chip.
//
// The "selected" date is rendered server-side (the chip label); this
// controller only paints the grid of day buttons inside the popover
// and handles month navigation + day selection. Day click navigates to
// `?before=YYYY-MM-DD`; the controller doesn't try to be a date input.
//
// Values:
//   selected — current selected date as YYYY-MM-DD (string).
//   path     — base path to navigate to with the new ?before= param.
export default class extends Controller {
  static targets = ["title", "grid"]
  static values = {
    selected: String,
    path: String
  }

  static MONTHS = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
  ]
  static DOW = ["S", "M", "T", "W", "T", "F", "S"]

  connect() {
    const seed = this.selectedValue
      ? this._parseISODate(this.selectedValue)
      : new Date()
    this.viewYear = seed.getFullYear()
    this.viewMonth = seed.getMonth()
    this.render()
  }

  prevMonth(event) {
    event.preventDefault()
    if (--this.viewMonth < 0) {
      this.viewMonth = 11
      this.viewYear--
    }
    this.render()
  }

  nextMonth(event) {
    event.preventDefault()
    if (++this.viewMonth > 11) {
      this.viewMonth = 0
      this.viewYear++
    }
    this.render()
  }

  pickDay(event) {
    event.preventDefault()
    const date = event.currentTarget.dataset.date
    if (!date) return
    const url = new URL(this.pathValue, window.location.origin)
    url.searchParams.set("before", date)
    window.location.href = url.toString()
  }

  pickToday(event) {
    event.preventDefault()
    const url = new URL(this.pathValue, window.location.origin)
    url.searchParams.delete("before")
    window.location.href = url.toString()
  }

  render() {
    const Months = this.constructor.MONTHS
    this.titleTarget.textContent = `${Months[this.viewMonth]} ${this.viewYear}`

    const firstDay = new Date(this.viewYear, this.viewMonth, 1)
    const startWeekday = firstDay.getDay()
    const daysInMonth = new Date(this.viewYear, this.viewMonth + 1, 0).getDate()
    const selected = this.selectedValue
    const today = this._today()

    const cells = []
    // Day-of-week header.
    this.constructor.DOW.forEach((d, i) => {
      cells.push(
        `<span class="text-center text-[10px] uppercase tracking-wide text-fg-subtle">${d}</span>`
      )
    })
    // Leading blanks.
    for (let i = 0; i < startWeekday; i++) {
      cells.push(`<span></span>`)
    }
    // Day buttons.
    for (let d = 1; d <= daysInMonth; d++) {
      const date =
        `${this.viewYear}-` +
        `${String(this.viewMonth + 1).padStart(2, "0")}-` +
        `${String(d).padStart(2, "0")}`
      const isSelected = date === selected
      const isToday = date === today
      let cls = "rounded p-1.5 text-xs tabular-nums hover:bg-bg-muted text-fg cursor-pointer"
      if (isSelected) cls = "rounded p-1.5 text-xs tabular-nums bg-brand text-fg-on-brand font-semibold"
      else if (isToday) cls = "rounded p-1.5 text-xs tabular-nums hover:bg-bg-muted text-brand font-semibold cursor-pointer"
      cells.push(
        `<button type="button" class="${cls}" data-date="${date}" data-action="click->calendar#pickDay">${d}</button>`
      )
    }
    this.gridTarget.innerHTML = cells.join("")
  }

  _today() {
    const d = new Date()
    return (
      `${d.getFullYear()}-` +
      `${String(d.getMonth() + 1).padStart(2, "0")}-` +
      `${String(d.getDate()).padStart(2, "0")}`
    )
  }

  _parseISODate(value) {
    // YYYY-MM-DD — construct a local-zone Date to avoid the
    // UTC-midnight pitfall.
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(value)
    if (!m) return new Date()
    return new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10))
  }
}
