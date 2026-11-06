import { Controller } from "@hotwired/stimulus"

// Starts loading lazy Turbo Frames a little before they scroll into
// view. Turbo's own `loading="lazy"` waits until a frame actually
// intersects the viewport, so on the home page every section scrolled
// to showed a blank placeholder for the half-second its commit_state
// work takes. This watches the same frames with a margin (one
// viewport height by default) and flips each to `loading="eager"` as
// it comes within range, which makes Turbo fetch its src right away.
//
// Frames already on screen are left alone: Turbo's own lazy observer
// has started fetching them, and flipping one to eager mid-request
// makes Turbo cancel that fetch and send it again, so the server did
// every on-screen section's work twice.
//
// The frames keep `loading="lazy"` in the markup, so without this
// controller (or without IntersectionObserver) they still load the
// stock way.
export default class extends Controller {
  static values = { margin: { type: String, default: "100% 0px" } }

  connect() {
    if (!("IntersectionObserver" in window)) return

    this.observer = new IntersectionObserver(this.prefetch, { rootMargin: this.marginValue })
    this.element.querySelectorAll("turbo-frame[loading='lazy'][src]").forEach((frame) => {
      this.observer.observe(frame)
    })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  prefetch = (entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return
      this.observer.unobserve(entry.target)
      if (this.onScreen(entry.boundingClientRect)) return
      entry.target.loading = "eager"
    })
  }

  onScreen(rect) {
    return rect.top < window.innerHeight && rect.bottom > 0
  }
}
