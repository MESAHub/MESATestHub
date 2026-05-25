import { Controller } from "@hotwired/stimulus"

// Click-to-open popover for matrix cells. The popover panel lives
// once at the matrix root (`data-popover-target="panel"`) and is
// positioned dynamically relative to the trigger cell on each open.
// Cell-specific content is rendered from an embedded JSON blob
// (`data-popover-target="data"`) keyed by "#{test_id}-#{computer_id}".
//
// Cells whose key isn't in the data blob are "clean" — no popover
// content to surface. They fall through to a direct navigation to
// the test-on-commit page via `data-popover-fallback-href`. That
// way every cell remains clickable and useful; the popover only
// fires where there's something worth saying.
//
// Closes on:
//   - Escape
//   - Click outside the panel
//   - Click on a different cell (which re-opens for that cell)
export default class extends Controller {
  static targets = ["cell", "panel", "content", "data", "dockedContent"]

  connect() {
    this._dataMap = null
    this._currentCell = null
    this._onDocClick = this._handleOutside.bind(this)
    this._onKey = this._handleKey.bind(this)
    // Capture the rail's inactive HTML once so `close()` can
    // restore it. The server renders the per-computer summary
    // into this target on first paint; we just stash it.
    this._railInactiveHTML = this.hasDockedContentTarget
      ? this.dockedContentTarget.innerHTML
      : ""
  }

  // The rail mode wins whenever the docked target is laid out
  // (offsetParent is null when the rail's `display: none` kicks
  // in below xl). This lets one controller serve both viewport
  // ranges without media-query coordination.
  _inDockedMode() {
    return this.hasDockedContentTarget && this.dockedContentTarget.offsetParent !== null
  }

  _renderTarget() {
    return this._inDockedMode() ? this.dockedContentTarget : this.contentTarget
  }

  disconnect() {
    document.removeEventListener("click", this._onDocClick, true)
    document.removeEventListener("keydown", this._onKey, true)
  }

  _loadData() {
    if (this._dataMap !== null) return this._dataMap
    if (!this.hasDataTarget) { this._dataMap = {}; return this._dataMap }
    try {
      this._dataMap = JSON.parse(this.dataTarget.textContent || "{}")
    } catch (_e) {
      this._dataMap = {}
    }
    return this._dataMap
  }

  open(event) {
    const cell = event.currentTarget
    const key = cell.dataset.popoverKey
    const data = this._loadData()
    const info = key && data[key]
    if (!info) {
      // Clean cell — let the fallback link take over.
      const href = cell.dataset.popoverFallbackHref
      if (href) window.location.href = href
      return
    }
    event.preventDefault()
    event.stopPropagation()
    this._clearActiveCell()
    this._currentCell = cell
    this._markActiveCell(cell)
    this._renderContent(info, cell)
    if (this._inDockedMode()) {
      // Rail is always visible; nothing to show/hide. We still
      // wire up the outside-click + escape listeners so the user
      // can clear the selection.
    } else {
      this._position(cell)
      this.panelTarget.hidden = false
    }
    document.addEventListener("click", this._onDocClick, true)
    document.addEventListener("keydown", this._onKey, true)
  }

  close() {
    if (this._inDockedMode()) {
      // Rail stays visible; reset to the inactive (computer
      // summary + hint) content captured on connect.
      if (this.hasDockedContentTarget) {
        this.dockedContentTarget.innerHTML = this._railInactiveHTML
      }
    } else {
      if (this.panelTarget.hidden) return
      this.panelTarget.hidden = true
    }
    this._clearActiveCell()
    document.removeEventListener("click", this._onDocClick, true)
    document.removeEventListener("keydown", this._onKey, true)
  }

  // Brand-color ring around the cell whose popover is open. Inline
  // box-shadow so it visibly extends beyond the cell rectangle
  // without affecting layout (outline shorthand respects border
  // radius poorly on some browsers; box-shadow is reliable here).
  // Also kills the hover-scale transform so the anchor cell stays
  // put while the popover is open and the user reads it.
  _markActiveCell(cell) {
    cell.style.boxShadow = "0 0 0 2px var(--color-brand), 0 0 0 4px var(--color-bg-elev)"
    cell.style.zIndex = "15"
    cell.dataset.popoverActive = "true"
  }

  _clearActiveCell() {
    if (!this._currentCell) return
    this._currentCell.style.boxShadow = ""
    this._currentCell.style.zIndex = ""
    delete this._currentCell.dataset.popoverActive
    this._currentCell = null
  }

  _handleOutside(event) {
    // Always allow clicks on another cell to switch selection
    // rather than closing — `open` re-fires for the new cell.
    const cellHit = event.target.closest('[data-popover-target="cell"]')
    if (cellHit && cellHit !== this._currentCell) return
    if (this._inDockedMode()) {
      // Rail stays visible. The only way to "close" is via the
      // explicit Clear button inside the rendered content — we
      // don't want a stray document click to wipe the user's
      // current selection while they're reading the panel.
      if (this.hasDockedContentTarget && this.dockedContentTarget.contains(event.target)) return
      return
    }
    if (this.panelTarget.contains(event.target)) return
    this.close()
  }

  _handleKey(event) {
    if (event.key === "Escape") this.close()
  }

  // Position the panel relative to the matrix container. Tries
  // below-right of the cell first; flips to above/left when the
  // panel would overflow the viewport.
  _position(cell) {
    const panel = this.panelTarget
    // Force a measure with display so getBoundingClientRect returns
    // real dimensions even on the first open.
    panel.hidden = false
    panel.style.visibility = "hidden"
    panel.style.left = "0px"
    panel.style.top = "0px"
    const containerRect = this.element.getBoundingClientRect()
    const cellRect = cell.getBoundingClientRect()
    const panelRect = panel.getBoundingClientRect()
    const gap = 6

    let left = cellRect.right - containerRect.left + gap
    let top = cellRect.top - containerRect.top
    // Flip horizontally if panel would overflow viewport.
    if (cellRect.right + gap + panelRect.width > window.innerWidth) {
      left = cellRect.left - containerRect.left - panelRect.width - gap
    }
    // Clamp top so panel stays in viewport (account for scroll).
    const scrollY = window.scrollY
    const cellViewportTop = cellRect.top
    const viewportH = window.innerHeight
    if (cellViewportTop + panelRect.height > viewportH - 12) {
      const adjustedViewportTop = Math.max(12, viewportH - panelRect.height - 12)
      top = adjustedViewportTop + scrollY - (containerRect.top + scrollY)
    }
    panel.style.left = `${Math.max(8, left)}px`
    panel.style.top = `${Math.max(0, top)}px`
    panel.style.visibility = ""
  }

  _renderContent(info, cell) {
    const flags = info.flags || {}
    const latest = info.latest || {}
    const instancePassed = !!latest.passed

    // Cross-computer status pill — what the matrix cell shows.
    // Distinct from the per-instance pass/fail of THIS computer's
    // submission; a passing-but-flagged cell carries amber here
    // while its mode line below still reads green for the local pass.
    const statusTone =
      info.status === "fail" ? "text-danger-soft-text" :
      info.status === "pending" ? "text-info-soft-text" :
      info.status === "no_build" ? "text-buildfail-soft-text" :
      (flags.fpe || flags.checksum) ? "text-warning-soft-text" :
      "text-success-soft-text"
    const headline =
      info.status === "fail" ? "FAIL" :
      info.status === "pending" ? "PENDING" :
      info.status === "no_build" ? "BUILD FAILED" :
      "PASS"

    // Flag chips listed individually rather than a vague
    // "(flagged)" tag — the design wants to communicate *what*
    // is flagged, so each gets its own pill.
    const flagPills = []
    if (flags.fpe) flagPills.push(`<span class="rounded-full bg-warning-soft text-warning-soft-text px-1.5 py-0.5 text-[10px] font-medium">FPE checks</span>`)
    if (flags.checksum) flagPills.push(`<span class="rounded-full bg-warning-soft text-warning-soft-text px-1.5 py-0.5 text-[10px] font-medium">checksum ≠</span>`)
    if (flags.inlists_full) flagPills.push(`<span class="rounded-full bg-info-soft text-info-soft-text px-1.5 py-0.5 text-[10px] font-medium">all inlists</span>`)

    const sectionRows = []

    // Mode line — colored to match the per-instance result so the
    // distinction between "this computer's run passed" (green) and
    // "the cross-computer view is amber" reads cleanly. Pass cells
    // get "Passing Mode: …", failures get "Failure: …".
    if (info.status === "fail" || info.status === "pass") {
      if (info.status === "fail") {
        const modeText = latest.failure_type ? `Failure: ${latest.failure_type}` : "Failure: (unknown)"
        sectionRows.push(`<div class="text-[12px] font-medium text-danger-soft-text">${this._esc(modeText)}</div>`)
      } else if (latest.success_type) {
        const tone = instancePassed ? "text-success-soft-text" : "text-fg"
        sectionRows.push(`<div class="text-[12px] font-medium ${tone}">Passing Mode: ${this._esc(latest.success_type)}</div>`)
      }
    } else if (info.status === "pending") {
      sectionRows.push(`<div class="text-[12px] text-info-soft-text">Submitted; no instance reported yet.</div>`)
    } else if (info.status === "no_build") {
      sectionRows.push(`<div class="text-[12px] text-buildfail-soft-text">Compilation failed on this computer — test wasn’t run.</div>`)
    }

    if (latest.summary_text) {
      sectionRows.push(`<pre class="max-h-32 overflow-auto rounded bg-bg-subtle px-2 py-1 font-mono text-[11px] text-fg-muted whitespace-pre-wrap break-words">${this._esc(latest.summary_text)}</pre>`)
    }

    if (latest.checksum) {
      const grouping = (info.checksum_match_count && info.checksum_match_total)
        ? ` <span class="${flags.checksum ? "text-warning-soft-text" : "text-fg-subtle"}">(${info.checksum_match_count}/${info.checksum_match_total} match)</span>`
        : ""
      sectionRows.push(
        `<div class="text-[11px] text-fg-muted"><span class="text-fg-subtle">checksum</span> <span class="font-mono text-fg">${this._esc(latest.checksum)}</span>${grouping}</div>`
      )
    }

    const meta = []
    if (latest.sdk_version) meta.push(`SDK ${this._esc(latest.sdk_version)}`)
    if (typeof latest.runtime_minutes === "number") meta.push(`${latest.runtime_minutes.toFixed(1)} min`)
    if (info.submission_count > 1) meta.push(`${info.submission_count} submissions`)
    if (info.agreement && info.agreement !== "single" && info.agreement !== "unanimous") {
      const word = info.agreement === "pass_fail_mixed" ? "instances disagreed (pass/fail)" : "instances disagreed (checksums)"
      meta.push(`<span class="text-warning-soft-text">${word}</span>`)
    }
    if (meta.length) {
      sectionRows.push(`<div class="text-[11px] text-fg-subtle">${meta.join(" · ")}</div>`)
    }

    // Optional scalar-metrics block. Surfaces things like steps,
    // retries, runtime, log_rel_run_E_err — the values a user
    // chasing degradation in a passing test wants to compare across
    // commits. Only renders when `info.metrics` is present (the
    // commit#show matrix doesn't populate it; the test_cases#show
    // History matrix does).
    if (info.metrics) {
      const metricRow = this._renderMetricsBlock(info.metrics)
      if (metricRow) sectionRows.push(metricRow)
    }

    const href = info.test_case_commit_href || cell.dataset.popoverFallbackHref || "#"
    const footerLink = `<a href="${this._esc(href)}" class="text-brand text-[11px] no-underline hover:opacity-80">View full test case details →</a>`
    const flagRow = flagPills.length
      ? `<div class="px-3 py-2 flex flex-wrap gap-1 border-b border-border-subtle bg-bg-subtle">${flagPills.join("")}</div>`
      : ""
    // Docked rail stays visible after clearing, so the action
    // reads "Clear selection" rather than "Close" — different
    // mental model from the floating popover that vanishes
    // entirely.
    const clearLabel = this._inDockedMode() ? "Clear selection" : "Close"

    // X close icon SVG — same stroke style as the rest of the
    // mesa_icon set. The button gets `-m-1 p-1` so its tap target
    // is ~28px (icon + padding) while visually sitting flush with
    // the header text — a workable touch target without bloating
    // the header layout.
    const closeIcon = `<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 4l8 8M12 4l-8 8"/></svg>`

    // Two header variants. When the payload includes a commit_sha,
    // the cell is per-commit (test_cases#show History matrix) — the
    // user already knows the test, so the SHA + message + author
    // belongs up top. Without commit_sha, fall back to the
    // test-name/computer-name header used by commit#show.
    const headerInner = info.commit_short_sha
      ? this._commitCentricHeader(info)
      : this._testCentricHeader(info)

    this._renderTarget().innerHTML = `
      <div class="px-3 py-2 border-b border-border-subtle flex items-start justify-between gap-3">
        ${headerInner}
        <div class="flex items-start gap-2 shrink-0">
          <span class="font-semibold ${statusTone} text-[11px] uppercase tracking-wide">${this._esc(headline)}</span>
          <button type="button" aria-label="Close" title="Close" data-action="popover#close" class="text-fg-subtle hover:text-fg hover:bg-bg-muted rounded p-1 -m-1 leading-none">
            ${closeIcon}
          </button>
        </div>
      </div>
      ${flagRow}
      <div class="px-3 py-2 space-y-2">
        ${sectionRows.join("")}
      </div>
      <div class="px-3 py-2 border-t border-border-subtle flex justify-between items-center">
        <button type="button" class="text-fg-subtle text-[11px] hover:text-fg" data-action="popover#close">${clearLabel}</button>
        ${footerLink}
      </div>
    `
  }

  _testCentricHeader(info) {
    return `
      <div class="min-w-0">
        <div class="font-mono text-[12px] text-fg truncate" title="${this._esc(info.module)}/${this._esc(info.test_name)}">
          <span class="text-fg-subtle">${this._esc(info.module)}/</span>${this._esc(info.test_name)}
        </div>
        <div class="text-[11px] text-fg-muted truncate">on <span class="font-mono text-fg">${this._esc(info.computer_name || "—")}</span></div>
      </div>`
  }

  _commitCentricHeader(info) {
    const ageBit = info.commit_time_ago ? ` <span class="text-fg-subtle">·</span> <span class="tabular-nums">${this._esc(info.commit_time_ago)}</span>` : ""
    const author = info.commit_author ? ` <span class="text-fg-subtle">·</span> ${this._esc(info.commit_author)}` : ""
    return `
      <div class="min-w-0">
        <div class="text-[12px] text-fg truncate">
          <span class="font-mono font-semibold text-brand">${this._esc(info.commit_short_sha)}</span>
          <span class="text-fg-subtle">on</span>
          <span class="font-mono text-fg">${this._esc(info.computer_name || "—")}</span>
        </div>
        <div class="text-[11px] text-fg-muted truncate" title="${this._esc(info.commit_message || "")}">${this._esc(info.commit_message || "")}</div>
        <div class="text-[11px] text-fg-subtle truncate">${author.replace(/^ <span class="text-fg-subtle">·<\/span> /, "")}${ageBit}</div>
      </div>`
  }

  // Compact two-column key/value grid for scalar metrics. Skips
  // zero/null values so the panel doesn't list "0 redos" type noise.
  // Field labels and number formatting are tuned for what the
  // History tab's degradation investigation actually wants — steps
  // and retries get integer formatting, runtime gets 2dp, the
  // accuracy proxy gets 3sf.
  _renderMetricsBlock(metrics) {
    const fmtInt = (v) => v == null ? null : Math.round(v).toLocaleString()
    const fmt2   = (v) => typeof v === "number" ? v.toFixed(2) : null
    const fmt3sf = (v) => typeof v === "number" ? v.toPrecision(3) : null

    const specs = [
      ["Runtime",        fmt2(metrics.runtime_minutes),     "min"],
      ["RAM (rn)",       fmt2(metrics.mem_rn_gb),           "GB"],
      ["Threads",        fmtInt(metrics.threads),           ""],
      ["Steps",          fmtInt(metrics.steps),             ""],
      ["Retries",        fmtInt(metrics.retries),           ""],
      ["Redos",          fmtInt(metrics.redos),             ""],
      ["Solver iters",   fmtInt(metrics.solver_iterations), ""],
      ["Solver calls",   fmtInt(metrics.solver_calls_made), ""],
      ["Solver fails",   fmtInt(metrics.solver_calls_failed), ""],
      ["log rel E err",  fmt3sf(metrics.log_rel_run_E_err), ""]
    ].filter(([, v]) => v != null && v !== "0")

    if (!specs.length) return null
    const items = specs.map(([label, val, unit]) =>
      `<div class="flex items-baseline justify-between gap-2 py-0.5">
         <span class="text-fg-subtle text-[11px]">${this._esc(label)}</span>
         <span class="font-mono tabular-nums text-fg text-[11px]">${this._esc(val)}${unit ? ` <span class="text-fg-subtle">${this._esc(unit)}</span>` : ""}</span>
       </div>`
    ).join("")
    return `
      <div class="rounded-md border border-border-subtle bg-bg-subtle/40 px-2 py-1.5">
        <div class="text-fg-subtle uppercase tracking-wide text-[10px] mb-1">Metrics</div>
        <div class="grid grid-cols-2 gap-x-3">${items}</div>
      </div>`
  }

  _esc(s) {
    if (s == null) return ""
    return String(s).replace(/[&<>"']/g, (c) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
    }[c]))
  }
}
