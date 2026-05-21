import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "mesa-theme"
const MODES = ["light", "dark", "system"]

// Controls the light/dark/system theme on the modern layout.
// The pre-paint script in `modern.html.haml` sets the initial `data-theme`
// from localStorage to avoid FOUC; this controller just handles cycling
// and persistence when the user clicks the toggle button.
export default class extends Controller {
  static targets = ["mode"]

  connect() {
    this.applyMode(this.currentMode)
    this.systemListener = () => {
      if (this.currentMode === "system") this.applyMode("system")
    }
    this.matchMedia?.addEventListener("change", this.systemListener)
  }

  disconnect() {
    this.matchMedia?.removeEventListener("change", this.systemListener)
  }

  cycle(event) {
    event.preventDefault()
    const next = MODES[(MODES.indexOf(this.currentMode) + 1) % MODES.length]
    localStorage.setItem(STORAGE_KEY, next)
    this.applyMode(next)
  }

  applyMode(mode) {
    const resolved = mode === "system" ? this.systemPreference : mode
    document.documentElement.setAttribute("data-theme", resolved)
    this.modeTargets.forEach((el) => {
      el.dataset.themeMode = mode
      const label = el.querySelector("[data-theme-label]")
      if (label) label.textContent = mode
    })
  }

  get currentMode() {
    const stored = localStorage.getItem(STORAGE_KEY)
    return MODES.includes(stored) ? stored : "system"
  }

  get matchMedia() {
    if (!window.matchMedia) return null
    this._mm ||= window.matchMedia("(prefers-color-scheme: dark)")
    return this._mm
  }

  get systemPreference() {
    return this.matchMedia?.matches ? "dark" : "light"
  }
}
