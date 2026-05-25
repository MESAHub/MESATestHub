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
    "frame", "placeholder", "content", "currentLabel", "computerButton",
    "downloadLink"
  ]
  static values = {
    urlTemplate: String,
    statusUrlTemplate: String,
    defaultComputer: String,
    activeTab: String,
    shortSha: String
  }

  connect() {
    this._loaded = false
    this._loading = false
    this._available = null
    this._currentComputer = this.defaultComputerValue
    this._onTabsChange = this._handleTabsChange.bind(this)
    this._onTabsRequest = this._handleTabsRequest.bind(this)
    document.addEventListener("tabs:change", this._onTabsChange)
    document.addEventListener("tabs:request", this._onTabsRequest)
    // Probe upstream so the tab strip can disable Logs before the
    // user clicks. Runs unconditionally — the side effect belongs
    // to the strip, not the active panel.
    this._probeAvailability()
  }

  disconnect() {
    document.removeEventListener("tabs:change", this._onTabsChange)
    document.removeEventListener("tabs:request", this._onTabsRequest)
  }

  _handleTabsChange(event) {
    if (event.detail && event.detail.tab === "logs") {
      this._maybeLoadInitial()
    }
  }

  // Cross-panel handoff: a "View build log" link in the Computers
  // tab packs `?tab=logs&computer=<name>` and the tabs controller
  // forwards both via `tabs:request`. Load that specific log even
  // if the upstream-probe-on-default-computer disabled the tab,
  // and re-enable the tab so subsequent picker clicks work.
  _handleTabsRequest(event) {
    if (!event.detail || event.detail.tab !== "logs") return
    const computer = event.detail.params && event.detail.params.computer
    if (!computer) return
    this._enableLogsTab()
    this.loadComputer(computer)
  }

  _enableLogsTab() {
    const link = document.querySelector('[data-tabs-target="link"][data-tab="logs"]')
    if (!link) return
    link.removeAttribute("aria-disabled")
    link.removeAttribute("title")
    link.classList.remove("opacity-50", "cursor-not-allowed")
  }

  _maybeLoadInitial() {
    if (this._loaded || this._loading) return
    if (this._available === false) return
    if (!this.defaultComputerValue) return
    this.loadComputer(this.defaultComputerValue)
  }

  // Probe the upstream log host (cheaply, server-side cached) and
  // either leave the tab as-is (logs available) or disable it with
  // a tooltip explaining why nothing's there. If the page loaded
  // straight into the Logs tab and the probe says it's empty, we
  // skip auto-loading; the placeholder copy still reads cleanly.
  async _probeAvailability() {
    const name = this.defaultComputerValue
    if (!name) {
      this._available = false
      this._disableLogsTab("No computers have submitted for this commit.")
      return
    }
    if (!this.hasStatusUrlTemplateValue) {
      // No probe wired up — fall through to the lazy-load path so
      // the tab still works.
      this._available = true
      return
    }
    const url = this.statusUrlTemplateValue.replace("__COMPUTER__", encodeURIComponent(name))
    try {
      const resp = await fetch(url, { headers: { Accept: "application/json" } })
      const data = resp.ok ? await resp.json() : { available: false }
      this._available = !!data.available
      if (!data.available) {
        this._disableLogsTab("Build logs aren’t available on the Flatiron host for this commit.")
        return
      }
      // Probe said available; if we're on the Logs tab already,
      // honor the deferred auto-load now that we know it'll
      // resolve.
      if (this.activeTabValue === "logs") this._maybeLoadInitial()
    } catch (_e) {
      // Network hiccup — don't penalize the tab; treat as available
      // and let the eventual fetch surface the real error.
      this._available = true
    }
  }

  _disableLogsTab(reason) {
    const link = document.querySelector('[data-tabs-target="link"][data-tab="logs"]')
    if (!link) return
    link.setAttribute("aria-disabled", "true")
    link.setAttribute("title", reason)
    link.classList.add("opacity-50", "cursor-not-allowed")
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
    this._updateDownloadLink(name)
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

  _updateDownloadLink(name) {
    if (!this.hasDownloadLinkTarget) return
    const href = this.urlTemplateValue.replace("__COMPUTER__", encodeURIComponent(name))
    this.downloadLinkTarget.setAttribute("href", href)
    const sha = this.hasShortShaValue ? this.shortShaValue : ""
    const filename = sha
      ? `build_log_${sha}_${name}.log`
      : `build_log_${name}.log`
    this.downloadLinkTarget.setAttribute("download", filename)
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
