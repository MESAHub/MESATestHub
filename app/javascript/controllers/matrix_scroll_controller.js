import { Controller } from "@hotwired/stimulus"

// Keeps the sticky matrix header band's column-name row in lockstep
// with the body grid's horizontal scroll position. The body wrapper
// is the scroll container (overflow-x: auto). The band stays outside
// any horizontal-scroll context — it's `position: sticky; top: 0`
// pinned to the document so vertical sticky still works — and we
// translate its inner row by the body's scrollLeft to align column
// headers with the cells that are currently visible.
//
// `overflow: clip` on the band keeps the translated content from
// visually spilling past the panel's right edge without setting up
// a scrolling context (which would trap vertical sticky inside the
// band).
export default class extends Controller {
  static targets = ["body", "headerInner"]

  connect() {
    // Apply the initial transform synchronously so the headers
    // don't briefly mis-align if the body wrapper boots up with a
    // non-zero scrollLeft (Safari restores scroll position from
    // back-forward navigation).
    this.sync()
  }

  sync() {
    if (!this.hasBodyTarget || !this.hasHeaderInnerTarget) return
    const x = this.bodyTarget.scrollLeft || 0
    this.headerInnerTarget.style.transform = `translateX(${-x}px)`
  }
}
