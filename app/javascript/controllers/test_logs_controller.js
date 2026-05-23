import { Controller } from "@hotwired/stimulus"

// Lazy-loaded per-test log viewer.
//
// Two URL axes — computer and type (out/mk/err) — so the template
// strings carry both placeholders:
//   urlTemplate:       .../test_logs/<mod>/<test>/__COMPUTER__/__TYPE__
//   statusUrlTemplate: .../test_logs_status/<mod>/<test>/__COMPUTER__
//
// Default to the server-picked computer (worst-first) and the
// `out` log type. On first reveal (or on a `tabs:request` deep
// link from a per-row "logs ↗" link) the controller fetches and
// renders the chosen log. Subsequent picker clicks refetch.
//
// HEAD probe on connect: per-computer, asking "does ANY of the
// three types exist for this computer?" — and remembers the
// per-type breakdown for default-type fallback. If no type is
// available for any computer in the list, the Logs tab gets
// aria-disabled.
export default class extends Controller {
  static targets = [
    "frame", "placeholder", "content", "computerButton", "typeButton",
    "downloadLink"
  ]
  static values = {
    urlTemplate: String,
    statusUrlTemplate: String,
    defaultComputer: String,
    defaultType: String,
    activeTab: String,
    shortSha: String,
    testName: String
  }

  connect() {
    this._loaded = false
    this._loading = false
    this._currentComputer = this.defaultComputerValue
    this._currentType = this.defaultTypeValue || "out"
    this._availability = new Map() // computer -> {out, mk, err}
    this._onTabsChange = this._handleTabsChange.bind(this)
    this._onTabsRequest = this._handleTabsRequest.bind(this)
    document.addEventListener("tabs:change", this._onTabsChange)
    document.addEventListener("tabs:request", this._onTabsRequest)
    this._probeAllComputers()
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

  // Cross-panel handoff. A per-row "logs ↗" link packs
  // `?tab=logs&computer=<name>` (and optionally `&type=<t>`); the
  // tabs controller forwards both via `tabs:request`. Honor the
  // computer + type the link asked for even if the probe hasn't
  // returned yet — the subsequent load surfaces the real error if
  // the file is missing.
  _handleTabsRequest(event) {
    if (!event.detail || event.detail.tab !== "logs") return
    const computer = event.detail.params && event.detail.params.computer
    const type = (event.detail.params && event.detail.params.type) || this._currentType
    if (!computer) return
    this._enableLogsTab()
    this.loadCombo(computer, type)
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
    if (!this._currentComputer) return
    this.loadCombo(this._currentComputer, this._currentType)
  }

  // Probe every computer in the picker, in parallel. Each probe
  // returns `{ available, types: { out, mk, err } }`. We store the
  // per-type breakdown so a missing default type can fall back to a
  // sibling that exists.
  async _probeAllComputers() {
    if (!this.hasStatusUrlTemplateValue) return
    const computers = this.computerButtonTargets.map((btn) => btn.dataset.computer).filter(Boolean)
    if (computers.length === 0) return

    const probes = computers.map(async (computer) => {
      const url = this.statusUrlTemplateValue.replace("__COMPUTER__", encodeURIComponent(computer))
      try {
        const resp = await fetch(url, { headers: { Accept: "application/json" } })
        const data = resp.ok ? await resp.json() : { available: false, types: {} }
        this._availability.set(computer, data.types || {})
        return data.available
      } catch (_e) {
        // Treat probe errors as available so the eventual GET
        // surfaces the real upstream message; same defensive
        // posture as the commit-show logs controller.
        this._availability.set(computer, {})
        return true
      }
    })

    const results = await Promise.all(probes)
    const anyAvailable = results.some(Boolean)
    if (!anyAvailable) {
      this._disableLogsTab("No upstream logs are available for this test on this commit.")
      return
    }
    // Mark computers with no logs visually muted so the user knows
    // not to bother clicking. Doesn't disable — a click still loads
    // and shows the friendly 404, which is informative.
    this._dimComputerButtons()

    // If the default type doesn't exist for the default computer
    // but a sibling type does, swap silently.
    const sample = this._availability.get(this._currentComputer) || {}
    if (sample[this._currentType] === false) {
      const fallback = ["out", "mk", "err"].find((t) => sample[t])
      if (fallback) this._currentType = fallback
    }

    // If page loaded straight into the Logs tab, the deferred
    // auto-load now has a clear picture of what to fetch.
    if (this.activeTabValue === "logs") this._maybeLoadInitial()
  }

  _dimComputerButtons() {
    this.computerButtonTargets.forEach((btn) => {
      const types = this._availability.get(btn.dataset.computer) || {}
      const anyType = Object.values(types).some(Boolean)
      btn.classList.toggle("opacity-50", !anyType)
      btn.title = anyType ? "" : "No logs uploaded for this computer"
    })
  }

  _disableLogsTab(reason) {
    const link = document.querySelector('[data-tabs-target="link"][data-tab="logs"]')
    if (!link) return
    link.setAttribute("aria-disabled", "true")
    link.setAttribute("title", reason)
    link.classList.add("opacity-50", "cursor-not-allowed")
  }

  selectComputer(event) {
    const name = event.currentTarget.dataset.computer
    if (!name) return
    // If the current type doesn't exist for the new computer but a
    // sibling does, switch silently so the user isn't greeted with
    // a 404 they didn't ask for.
    const types = this._availability.get(name) || {}
    let type = this._currentType
    if (types[type] === false) {
      const fallback = ["out", "mk", "err"].find((t) => types[t])
      if (fallback) type = fallback
    }
    if (name === this._currentComputer && type === this._currentType) return
    this.loadCombo(name, type)
  }

  selectType(event) {
    const type = event.currentTarget.dataset.type
    if (!type || type === this._currentType) return
    this.loadCombo(this._currentComputer, type)
  }

  async loadCombo(computer, type) {
    this._loading = true
    this._currentComputer = computer
    this._currentType = type
    this._updateButtonStates(computer, type)
    this._updateDownloadLink(computer, type)
    this._showLoading(computer, type)

    const url = this.urlTemplateValue
      .replace("__COMPUTER__", encodeURIComponent(computer))
      .replace("__TYPE__", encodeURIComponent(type))

    try {
      const resp = await fetch(url, { headers: { Accept: "text/plain" } })
      const body = await resp.text()
      if (resp.status === 404) {
        this._showNotFound(body)
      } else if (!resp.ok) {
        this._showError(resp.status, body)
      } else {
        this._showLog(body)
        this._loaded = true
      }
    } catch (err) {
      this._showError("network", err && err.message)
    } finally {
      this._loading = false
    }
  }

  _updateDownloadLink(computer, type) {
    if (!this.hasDownloadLinkTarget) return
    const href = this.urlTemplateValue
      .replace("__COMPUTER__", encodeURIComponent(computer))
      .replace("__TYPE__", encodeURIComponent(type))
    this.downloadLinkTarget.setAttribute("href", href)
    const sha = this.hasShortShaValue ? this.shortShaValue : ""
    const test = this.hasTestNameValue ? this.testNameValue : "test"
    const filename = `${test}_${sha}_${computer}_${type}.txt`
    this.downloadLinkTarget.setAttribute("download", filename)
  }

  _updateButtonStates(activeComputer, activeType) {
    this.computerButtonTargets.forEach((btn) => {
      const active = btn.dataset.computer === activeComputer
      btn.classList.toggle("border-brand", active)
      btn.classList.toggle("bg-brand-soft", active)
      btn.classList.toggle("text-brand-soft-text", active)
      btn.classList.toggle("border-border", !active)
      btn.classList.toggle("bg-bg-elev", !active)
      btn.classList.toggle("text-fg-muted", !active)
    })
    this.typeButtonTargets.forEach((btn) => {
      const active = btn.dataset.type === activeType
      btn.classList.toggle("bg-brand-soft", active)
      btn.classList.toggle("text-brand-soft-text", active)
      btn.classList.toggle("text-fg-muted", !active)
    })
  }

  _showLoading(computer, type) {
    if (!this.hasPlaceholderTarget) return
    this.placeholderTarget.classList.remove("hidden")
    this.placeholderTarget.innerHTML = `
      <span class="inline-flex items-center gap-2 text-fg-muted text-sm">
        <span class="inline-block h-3 w-3 rounded-full border-2 border-border-strong border-t-brand animate-spin"></span>
        <span>Loading <span class="font-mono">${this._esc(type)}.txt</span> for <span class="font-mono">${this._esc(computer)}</span>…</span>
      </span>
    `
    if (this.hasContentTarget) this.contentTarget.classList.add("hidden")
  }

  _showLog(body) {
    if (this.hasPlaceholderTarget) this.placeholderTarget.classList.add("hidden")
    if (!this.hasContentTarget) return
    this.contentTarget.classList.remove("hidden")
    this.contentTarget.textContent = body.length ? body : "(empty log)"
  }

  // 404 from the server is the "this exact log file wasn't
  // uploaded" case. The server-side message is already friendly
  // and references the sibling types; render it in a muted info
  // tone rather than the danger tone the controller uses for real
  // upstream errors.
  _showNotFound(body) {
    if (this.hasPlaceholderTarget) {
      this.placeholderTarget.classList.remove("hidden")
      if (this.hasContentTarget) this.contentTarget.classList.add("hidden")
      this.placeholderTarget.innerHTML = `
        <div class="text-fg-muted text-sm whitespace-pre-line">${this._esc(body)}</div>
      `
    }
  }

  _showError(status, body) {
    if (!this.hasPlaceholderTarget) return
    this.placeholderTarget.classList.remove("hidden")
    if (this.hasContentTarget) this.contentTarget.classList.add("hidden")
    const detail = body ? this._esc(String(body).slice(0, 400)) : ""
    this.placeholderTarget.innerHTML = `
      <div class="text-danger-soft-text text-sm">
        Could not load log (${this._esc(String(status))}).
      </div>
      ${detail ? `<div class="mt-2 text-fg-subtle text-[11px] font-mono">${detail}</div>` : ""}
    `
  }

  _esc(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
    }[c]))
  }
}
