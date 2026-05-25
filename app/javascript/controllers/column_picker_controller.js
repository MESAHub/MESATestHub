import { Controller } from "@hotwired/stimulus"

// Toggles visibility of columns on the test-on-commit instances
// table. Each `<th>` and `<td>` participating in the picker carries
// a `data-col="<id>"` attribute; this controller hides cells whose
// id isn't in the current active set.
//
// Active set is a space-separated string of ids, mirrored on the
// controller's `data-column-picker-active-value` attribute so the
// HAML side can prime it from a server-computed default. After every
// user-driven change the new set is written to `localStorage` under
// the configured `storage-key-value`, so a user's column choice
// survives navigations.
//
// Presets are passed in as a JSON blob (`presets-value`) keyed by
// preset name (e.g. "default" → "computer variant runtime ..."). The
// "all" preset doubles as a one-click "show every column".
export default class extends Controller {
  static targets = ["table", "checkbox", "label", "groupToggle", "count", "preset"]
  static values = {
    active: { type: String, default: "" },
    default: { type: String, default: "" },
    storageKey: { type: String, default: "mesa.test_on_commit.columns.v1" },
    presets: { type: String, default: "{}" }
  }

  connect() {
    let presets = {}
    try { presets = JSON.parse(this.presetsValue || "{}") } catch (e) { presets = {} }
    this._presets = presets

    // Hydrate from localStorage if present. Falls back to the
    // server-supplied default. Filters against the universe of known
    // ids so a stale localStorage from a previous schema can't leave
    // checkboxes dangling.
    const stored = this._readStored()
    const initial = stored ?? this.activeValue
    this.activeValue = this._sanitize(initial)
    this.apply()
  }

  toggleColumn(event) {
    const id = event.currentTarget.dataset.column
    if (!id) return
    const set = this._activeSet()
    if (event.currentTarget.checked) {
      set.add(id)
    } else {
      set.delete(id)
    }
    this.activeValue = [...set].join(" ")
    this._persist()
    this.apply()
  }

  toggleGroup(event) {
    event.preventDefault()
    const ids = (event.currentTarget.dataset.groupColumns || "").split(/\s+/).filter(Boolean)
    if (!ids.length) return
    const set = this._activeSet()
    const allOn = ids.every((id) => set.has(id))
    if (allOn) {
      ids.forEach((id) => set.delete(id))
    } else {
      ids.forEach((id) => set.add(id))
    }
    this.activeValue = [...set].join(" ")
    this._persist()
    this.apply()
  }

  applyPreset(event) {
    const name = event.currentTarget.dataset.preset
    if (!name) return
    const ids = this._presets[name]
    if (!ids) return
    this.activeValue = ids
    this._persist()
    this.apply()
  }

  resetToDefault() {
    this.activeValue = this.defaultValue
    this._persist()
    this.apply()
  }

  apply() {
    const set = this._activeSet()

    // Toggle visibility of every `data-col` cell on the table. Set
    // `hidden` on the element so the browser drops it from the table
    // layout entirely — sibling cells reflow into the freed width.
    if (this.hasTableTarget) {
      this.tableTarget.querySelectorAll("[data-col]").forEach((cell) => {
        const id = cell.dataset.col
        cell.hidden = !set.has(id)
      })
    }

    // Sync checkbox state + label color.
    this.checkboxTargets.forEach((cb) => {
      cb.checked = set.has(cb.dataset.column)
    })
    this.labelTargets.forEach((lbl) => {
      const on = set.has(lbl.dataset.column)
      lbl.classList.toggle("text-fg", on)
      lbl.classList.toggle("text-fg-muted", !on)
    })

    // Highlight active preset chip.
    const total = this._totalColumns()
    if (this.hasCountTarget) {
      this.countTarget.textContent = `${set.size}/${total}`
    }
    if (this.hasPresetTarget) {
      this.presetTargets.forEach((btn) => {
        const ids = this._presets[btn.dataset.preset] || ""
        const presetSet = new Set(ids.split(/\s+/).filter(Boolean))
        const matches = presetSet.size === set.size && [...presetSet].every((id) => set.has(id))
        btn.classList.toggle("bg-brand-soft", matches)
        btn.classList.toggle("text-brand-soft-text", matches)
        btn.classList.toggle("text-fg-muted", !matches)
        btn.classList.toggle("bg-bg-elev", !matches)
      })
    }
  }

  _activeSet() {
    return new Set((this.activeValue || "").split(/\s+/).filter(Boolean))
  }

  _sanitize(value) {
    const known = new Set(this._knownColumns())
    return (value || "")
      .split(/\s+/)
      .filter((id) => id && known.has(id))
      .join(" ")
  }

  _knownColumns() {
    // The union of every preset is the universe of valid ids. Cheaper
    // than scraping the DOM every connect.
    const ids = new Set()
    Object.values(this._presets).forEach((csv) => {
      csv.split(/\s+/).forEach((id) => id && ids.add(id))
    })
    return [...ids]
  }

  _totalColumns() {
    return this._knownColumns().length
  }

  _readStored() {
    try {
      const v = window.localStorage.getItem(this.storageKeyValue)
      if (typeof v !== "string" || !v) return null
      return this._sanitize(v)
    } catch (e) {
      return null
    }
  }

  _persist() {
    try {
      window.localStorage.setItem(this.storageKeyValue, this.activeValue || "")
    } catch (e) { /* localStorage disabled — silently skip */ }
  }
}
