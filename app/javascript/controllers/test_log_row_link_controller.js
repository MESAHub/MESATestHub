import { Controller } from "@hotwired/stimulus"

// Per-instance-row "logs ↗" link that jumps to the Logs tab with
// the matching computer pre-selected. On connect, probes the
// upstream and hides the link if no logs exist for this (commit,
// computer, test). Mirrors the pattern used by
// computer_card_controller on the commit-show Computers tab.
//
// The probe shares a server-side cache (10-minute TTL) with the
// test_logs controller's probe, so N row links per page is N
// cache hits after the first reveal.
export default class extends Controller {
  static values = { probeUrl: String }

  connect() {
    this._probe()
  }

  async _probe() {
    if (!this.hasProbeUrlValue) return
    try {
      const resp = await fetch(this.probeUrlValue, { headers: { Accept: "application/json" } })
      const data = resp.ok ? await resp.json() : { available: false }
      if (!data.available) {
        this.element.hidden = true
      }
    } catch (_e) {
      // Network hiccup — leave the link visible. Clicking through
      // surfaces the friendly 404 from the server.
    }
  }
}
