import { Controller } from "@hotwired/stimulus"

// Per-card upstream-log probe for the Computers tab. Each card
// optionally exposes a "logs ↗" / "build logs ↗" link that routes
// through the in-page Logs tab. We don't know server-side whether
// the upstream log host actually has a file for this commit +
// computer; the link would lead the user to an empty Logs panel.
//
// This controller probes the same `build_log_status/:computer`
// endpoint the Logs tab uses (10-min server-side cache) and either
// leaves the link enabled or replaces it with a small grey
// "no log available" placeholder. The probe fires on connect so the
// answer is ready by the time the user reads the card.
export default class extends Controller {
  static targets = ["link", "noLog"]
  static values = { statusUrl: String }

  connect() {
    if (!this.hasLinkTarget) return
    if (!this.hasStatusUrlValue) return
    this._probe()
  }

  async _probe() {
    try {
      const resp = await fetch(this.statusUrlValue, { headers: { Accept: "application/json" } })
      const data = resp.ok ? await resp.json() : { available: false }
      if (data.available) return // link stays as-is
      this._showUnavailable()
    } catch (_e) {
      // Network glitch — leave the link enabled and let the Logs
      // tab surface the real error if the user clicks through.
    }
  }

  _showUnavailable() {
    this.linkTarget.hidden = true
    if (this.hasNoLogTarget) this.noLogTarget.hidden = false
  }
}
