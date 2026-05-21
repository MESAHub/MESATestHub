import { Controller } from "@hotwired/stimulus"

// Tab strip on the commit detail page. Server pre-renders all panels;
// the controller toggles each one's `hidden` attribute and updates the
// active tab's underline. Click also updates ?tab=… via
// history.replaceState so the URL stays bookmarkable without a full
// page reload — Turbo would do this for us if we wanted, but the
// panels are server-rendered up-front and toggling DOM is cheaper.
//
// Banners' "See computers" / "See mixed tests" / "View diff" buttons
// route through `switchFromLink` so a stray relative `?tab=foo` link
// doesn't force a full navigation either.
export default class extends Controller {
  static targets = ["link", "panel"]
  static values = { active: String }

  connect() {
    this.applyActive(this.activeValue)
  }

  switch(event) {
    event.preventDefault()
    // Logs (and any other tab) can flip to aria-disabled at runtime
    // — e.g., when the logs controller probes upstream and finds
    // nothing. Honor that here so the click does nothing instead of
    // navigating to a broken panel.
    if (event.currentTarget.getAttribute("aria-disabled") === "true") return
    const tab = event.currentTarget.dataset.tab
    if (!tab || tab === this.activeValue) return
    this.activeValue = tab
    this.applyActive(tab)
    this.pushUrl(tab)
  }

  switchFromLink(event) {
    event.preventDefault()
    const url = new URL(event.currentTarget.getAttribute("href"), window.location.href)
    const tab = url.searchParams.get("tab")
    if (!tab) return
    this.activeValue = tab
    this.applyActive(tab)
    this.pushUrl(tab)

    // If the link carries a `filter` param (banner shortcut from
    // "See failing tests", "See mixed tests"), broadcast it so the
    // target panel's filter controller can apply it. We bubble the
    // event up to `document` so per-panel listeners can subscribe
    // anywhere in the tree.
    const filter = url.searchParams.get("filter")
    if (filter) {
      this.dispatch("filter", { detail: { tab, filter }, bubbles: true, prefix: "tabs" })
    }
  }

  applyActive(active) {
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.tab !== active
    })
    this.linkTargets.forEach((link) => {
      const on = link.dataset.tab === active
      link.setAttribute("aria-selected", on ? "true" : "false")
      link.classList.toggle("text-fg", on)
      link.classList.toggle("text-fg-muted", !on)
      link.classList.toggle("border-brand", on)
      link.classList.toggle("border-transparent", !on)
      link.classList.toggle("-mb-px", on)
    })
    // Surface the change so per-panel controllers (e.g. logs) can
    // lazy-load on first reveal. Bubbles so listeners can subscribe
    // at any ancestor — we use it on the logs controller scope.
    this.dispatch("change", { detail: { tab: active }, bubbles: true })
  }

  pushUrl(tab) {
    const url = new URL(window.location.href)
    url.searchParams.set("tab", tab)
    window.history.replaceState({}, "", url.toString())
  }
}
