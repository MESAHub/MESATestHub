import { Controller } from "@hotwired/stimulus"

// Lazy-loaded build-log viewer.
//
// The first time the Logs tab becomes visible (either it's the
// default tab on page load, or the user clicks it later) the
// controller fetches the default computer's build.log through the
// Rails proxy and renders it. Subsequent computer-button clicks
// refetch and replace.
//
// We don't load on connect()-without-visibility because the panel
// is server-rendered but hidden — fetching then would defeat the
// "save bandwidth" point of lazy loading. The tabs controller
// dispatches a `tabs:change` event when the user switches; we
// listen on the document and only act when our tab is now active.
//
// The URL template comes from the server as
// `/.../build_log/__COMPUTER__` so the controller can substitute
// the chosen computer name without re-deriving the path.
export default class extends Controller {
  static targets = [
    "frame", "placeholder", "content", "currentLabel", "computerButton"
  ]
  static values = {
    urlTemplate: String,
    defaultComputer: String,
    activeTab: String
  }

  connect() {
    this._loaded = false
    this._loading = false
    this._currentComputer = this.defaultComputerValue
    this._onTabsChange = this._handleTabsChange.bind(this)
    document.addEventListener("tabs:change", this._onTabsChange)
    // If the page loaded directly into the Logs tab (server-side
    // default-tab logic or a `?tab=logs` deep link), kick the fetch
    // off now — there's no tabs:change to wait for.
    if (this.activeTabValue === "logs" && this.defaultComputerValue) {
      this._maybeLoadInitial()
    }
  }

  disconnect() {
    document.removeEventListener("tabs:change", this._onTabsChange)
  }

  _handleTabsChange(event) {
    if (event.detail && event.detail.tab === "logs") {
      this._maybeLoadInitial()
    }
  }

  _maybeLoadInitial() {
    if (this._loaded || this._loading) return
    if (!this.defaultComputerValue) return
    this.loadComputer(this.defaultComputerValue)
  }

  selectComputer(event) {
    const name = event.currentTarget.dataset.logsComputer
    if (!name || name === this._currentComputer) return
    this.loadComputer(name)
  }

  async loadComputer(name) {
    this._loading = true
    this._currentComputer = name
    if (this.hasCurrentLabelTarget) this.currentLabelTarget.textContent = name
    this._updateButtonStates(name)
    this._showLoading(name)

    const url = this.urlTemplateValue.replace("__COMPUTER__", encodeURIComponent(name))

    try {
      const resp = await fetch(url, { headers: { Accept: "text/plain" } })
      const body = await resp.text()
      if (!resp.ok) {
        this._showError(resp.status, body)
        return
      }
      this._showLog(body)
      this._loaded = true
    } catch (err) {
      this._showError("network", err && err.message)
    } finally {
      this._loading = false
    }
  }

  _updateButtonStates(activeName) {
    this.computerButtonTargets.forEach((btn) => {
      const active = btn.dataset.logsComputer === activeName
      btn.classList.toggle("border-brand", active)
      btn.classList.toggle("bg-brand-soft", active)
      btn.classList.toggle("text-brand-soft-text", active)
      btn.classList.toggle("border-border", !active)
      btn.classList.toggle("bg-bg-elev", !active)
      btn.classList.toggle("text-fg-muted", !active)
    })
  }

  _showLoading(name) {
    if (!this.hasPlaceholderTarget) return
    this.placeholderTarget.classList.remove("hidden")
    this.placeholderTarget.innerHTML = `
      <span class="inline-flex items-center gap-2 text-fg-muted text-sm">
        <span class="inline-block h-3 w-3 rounded-full border-2 border-border-strong border-t-brand animate-spin"></span>
        <span>Loading build log for <span class="font-mono">${this._escape(name)}</span>…</span>
      </span>
    `
    if (this.hasContentTarget) this.contentTarget.classList.add("hidden")
  }

  _showLog(body) {
    if (this.hasPlaceholderTarget) this.placeholderTarget.classList.add("hidden")
    if (!this.hasContentTarget) return
    this.contentTarget.classList.remove("hidden")
    // textContent (not innerHTML) so any HTML-looking bytes in the
    // log file are inert.
    this.contentTarget.textContent = body.length ? body : "(empty log)"
  }

  _showError(status, body) {
    if (!this.hasPlaceholderTarget) return
    this.placeholderTarget.classList.remove("hidden")
    if (this.hasContentTarget) this.contentTarget.classList.add("hidden")
    const detail = body ? this._escape(String(body).slice(0, 400)) : ""
    this.placeholderTarget.innerHTML = `
      <div class="text-danger-soft-text text-sm">
        Could not load build log (${this._escape(String(status))}).
      </div>
      ${detail ? `<div class="mt-2 text-fg-subtle text-[11px] font-mono">${detail}</div>` : ""}
    `
  }

  _escape(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
    }[c]))
  }
}
