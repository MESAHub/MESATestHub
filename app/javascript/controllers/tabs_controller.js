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
  }

  pushUrl(tab) {
    const url = new URL(window.location.href)
    url.searchParams.set("tab", tab)
    window.history.replaceState({}, "", url.toString())
  }
}
