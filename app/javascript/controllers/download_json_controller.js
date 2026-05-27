import { Controller } from "@hotwired/stimulus"

// Fetches the full (non-paginated) JSON result set from
// /test_instances/search.json and saves it as a file. Authentication
// rides on the existing browser session — the HTML search page is
// already gated to logged-in users, so the fetch inherits that
// cookie. When the result set is bigger than `threshold`, ask the
// user to confirm first via a native <dialog> modal — the server
// will happily ship 100k rows in one envelope but the user is
// usually better off going through `mesa_test count` first.
//
// Targets:
//   button — the trigger button. We swap its label to "Preparing…"
//            during the fetch and restore on completion. Disabled
//            while in flight to prevent double-fires.
//
// Values:
//   count     (Number) — total rows the query matches (Kaminari's
//                        total_count from the server).
//   threshold (Number) — show the confirm modal above this row count.
//   query     (String) — the query_text to re-run for the JSON path.
//   queryLabel (String) — human-readable rendering of the query
//                         (defaults to `query`) for the modal text.
export default class extends Controller {
  static targets = ["button"]
  static values = {
    count: Number,
    threshold: { type: Number, default: 5000 },
    query: String,
    queryLabel: String
  }

  async start(event) {
    event.preventDefault()
    if (this.countValue > this.thresholdValue) {
      const proceed = await this._confirmLarge()
      if (!proceed) return
    }
    await this._download()
  }

  // Native <dialog>-backed confirm. Returns a Promise<boolean>.
  // Native dialog gives us focus-trap, ESC-to-cancel, and backdrop
  // styling for free — no library, no extra DOM lifecycle to manage.
  _confirmLarge() {
    return new Promise((resolve) => {
      const dialog = document.createElement("dialog")
      dialog.className = "rounded-lg border border-border bg-bg-elev p-0 max-w-md"
      dialog.style.boxShadow = "var(--shadow-card-lg)"

      const queryLabel = this.queryLabelValue || this.queryValue || "(no query)"
      const approxBytes = this.countValue * 800 // rough per-row average
      const sizeMB = (approxBytes / 1024 / 1024).toFixed(1)

      dialog.innerHTML = `
        <div class="px-5 py-4 border-b border-border-subtle">
          <div class="text-fg font-medium text-[14px]">Download ${this.countValue.toLocaleString()} test instances?</div>
        </div>
        <div class="px-5 py-4 space-y-3 text-[13px] text-fg-muted">
          <p>
            This query returns
            <span class="font-mono text-fg">${this.countValue.toLocaleString()}</span>
            rows. The JSON payload will be roughly
            <span class="font-mono text-fg">${sizeMB} MB</span>
            and will be sent in one response.
          </p>
          <p>
            If you only need a sample, narrow the query first
            (e.g., add a <span class="font-mono">commit_datetime</span> range).
          </p>
          <p class="text-fg-subtle text-[12px]">
            Query: <span class="font-mono text-fg">${this._escapeHTML(queryLabel)}</span>
          </p>
        </div>
        <div class="px-5 py-3 border-t border-border-subtle flex justify-end gap-2 bg-bg-subtle">
          <button type="button" data-action="cancel" class="mesa-btn" style="padding: 5px 14px; font-size: 12px;">Cancel</button>
          <button type="button" data-action="confirm" class="mesa-btn mesa-btn-primary" style="padding: 5px 14px; font-size: 12px;">Download anyway</button>
        </div>
      `

      const cleanup = (result) => {
        dialog.close()
        dialog.remove()
        resolve(result)
      }

      dialog.querySelector('[data-action="cancel"]').addEventListener("click", () => cleanup(false))
      dialog.querySelector('[data-action="confirm"]').addEventListener("click", () => cleanup(true))
      // ESC / backdrop click → cancel
      dialog.addEventListener("cancel", (e) => { e.preventDefault(); cleanup(false) })
      dialog.addEventListener("click", (e) => { if (e.target === dialog) cleanup(false) })

      document.body.appendChild(dialog)
      dialog.showModal()
    })
  }

  async _download() {
    const btn = this.hasButtonTarget ? this.buttonTarget : this.element
    const originalLabel = btn.querySelector("[data-label]")?.textContent
    if (originalLabel) btn.querySelector("[data-label]").textContent = "Preparing…"
    btn.disabled = true

    try {
      const url = `/test_instances/search.json?query_text=${encodeURIComponent(this.queryValue)}`
      const response = await fetch(url, {
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
      if (!response.ok) {
        alert(`Download failed (HTTP ${response.status}). Try again or pull a smaller result set via mesa_test.`)
        return
      }
      const blob = await response.blob()
      const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19)
      const a = document.createElement("a")
      a.href = URL.createObjectURL(blob)
      a.download = `mesa-test-instances-${stamp}.json`
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      URL.revokeObjectURL(a.href)
    } catch (e) {
      alert(`Download failed: ${e.message}`)
    } finally {
      if (originalLabel) btn.querySelector("[data-label]").textContent = originalLabel
      btn.disabled = false
    }
  }

  _escapeHTML(s) {
    const div = document.createElement("div")
    div.textContent = s
    return div.innerHTML
  }
}
