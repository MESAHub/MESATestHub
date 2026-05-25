import { Controller } from "@hotwired/stimulus"
import uPlot from "uplot"

// Trend chart for the test_cases#show Trend tab. Reads a JSON
// payload embedded by `TestCase#trend_payload`, renders a uPlot
// line chart with one series per (computer, threads, run_optional)
// config (top-3 by instance count in the window), and overlays a
// status strip at the bottom of the plot area so the user can see
// "this metric jumped at the same commit where status flipped."
//
// The chart's X axis is commit *index* along the window, NOT time
// — equal spacing makes regression points visually obvious. The
// time information lives in the tooltip.
//
// Interactions:
//   - Hover     → tooltip with SHA, message, per-series values
//   - Click     → re-center the toolbar (URL ?center=<sha>=) on that commit
//   - Metric    → <select> swaps which series array drives the y axis
//   - Series    → chips toggle individual configs on/off
//   - Theme     → MutationObserver on `<html data-theme>` triggers a redraw
//
// Empty states:
//   - 0 commits in window         → "no commits"
//   - 0 configs with shared data  → "not enough data for a common config"
//   - 0 data points after toggles → handled by uPlot (all-null series)
export default class extends Controller {
  static targets = ["chart", "metricPicker", "seriesChip", "data", "empty"]
  static values  = {
    // Server seeds the metric from ?metric=<id> (or the default if
    // the URL is silent). Keeping the source of truth in the value
    // means the <select>'s server-rendered `selected` attribute and
    // the chart agree without a sync-on-connect dance.
    metric:    { type: String, default: "" },
    // The anchor commit's short_sha — server-known — so we can
    // highlight its X position on the chart and label it cleanly.
    anchorSha: { type: String, default: "" }
  }

  connect() {
    this._loadPayload()
    if (!this.payload || this.payload.commits.length === 0) {
      this._renderEmpty("No commits in this window. Try a wider window or pan toward HEAD.")
      return
    }
    if (this.payload.configs.length === 0) {
      this._renderEmpty("Not enough data: no commits in this window were run with a common (computer, threads, run-mode) config. Try a wider window or check the History tab to see which configs have submitted.")
      return
    }
    this.currentMetric = this.metricValue || this.payload.default_metric
    this.anchorIdx = this.anchorShaValue
      ? this.payload.commits.findIndex(c => c.sha === this.anchorShaValue)
      : -1
    this.visibleSeries = new Set(this.payload.configs.map(c => c.key))
    this._buildChart()
    this._observeTheme()
    this._observeVisibility()
    this._onResize = () => this._resize()
    window.addEventListener("resize", this._onResize)
  }

  disconnect() {
    window.removeEventListener("resize", this._onResize)
    if (this._themeObserver) this._themeObserver.disconnect()
    if (this._visibilityObserver) this._visibilityObserver.disconnect()
    if (this.chart) { this.chart.destroy(); this.chart = null }
  }

  // ─── User interactions ────────────────────────────────────────

  selectMetric(event) {
    this.currentMetric = event.currentTarget.value
    // Persist to the URL so a subsequent re-center (which is a full
    // navigation) keeps the chosen metric. replaceState — not push
    // — so the back button doesn't accumulate one entry per dropdown
    // change.
    const url = new URL(window.location.href)
    url.searchParams.set("metric", this.currentMetric)
    window.history.replaceState({}, "", url.toString())
    // Server-rendered toolbar / tab-strip links were built with
    // whatever metric was on the URL at page render time. After a
    // JS-only change they're stale — update any link that points
    // at THIS test_case_path so a pan/window/tab nav carries the
    // new metric. Links to other test cases or other branches are
    // left alone (changing tests resets metric, intentionally).
    this._propagateMetricToLinks(this.currentMetric)
    this._updateData()
  }

  _propagateMetricToLinks(metric) {
    const here = window.location.pathname
    document.querySelectorAll("a[href]").forEach(a => {
      let u
      try { u = new URL(a.href) } catch (_) { return }
      if (u.origin !== window.location.origin) return
      if (u.pathname !== here) return
      u.searchParams.set("metric", metric)
      a.href = u.toString()
    })
  }

  toggleSeries(event) {
    const key = event.currentTarget.dataset.seriesKey
    if (!key) return
    if (this.visibleSeries.has(key)) this.visibleSeries.delete(key)
    else this.visibleSeries.add(key)
    this._syncChipState()
    this._updateData()
  }

  // ─── Payload + data plumbing ──────────────────────────────────

  _loadPayload() {
    try { this.payload = JSON.parse(this.dataTarget.textContent || "null") }
    catch (_e) { this.payload = null }
  }

  // Returns [xs, ...config_arrays] in the order uPlot wants. Hidden
  // series get an all-null array so uPlot draws nothing for them
  // (and the legend chip can still toggle them back on).
  _buildData() {
    const xs = this.payload.commits.map((_, i) => i)
    const cfgArrays = this.payload.configs.map(cfg => {
      if (!this.visibleSeries.has(cfg.key)) return xs.map(() => null)
      return this.payload.series[this.currentMetric]?.[cfg.key] ?? xs.map(() => null)
    })
    return [xs, ...cfgArrays]
  }

  _updateData() {
    if (!this.chart) return
    this.chart.setData(this._buildData())
  }

  // ─── Chart construction ───────────────────────────────────────

  _buildChart() {
    const data = this._buildData()
    const tokens = this._readTokens()

    const series = [
      {},
      ...this.payload.configs.map(cfg => ({
        label: cfg.label,
        stroke: cfg.color,
        width: 1.75,
        spanGaps: false,
        points: { show: true, size: 5, stroke: cfg.color, fill: cfg.color },
        value: (_u, v) => v == null ? "—" : this._fmtNumber(v)
      }))
    ]

    const xs = this.payload.commits
    // Only three X labels are meaningful here: "← older" at the
    // left edge, the anchor SHA at its position, "newer →" at the
    // right. Per-tick SHAs were just noise — users hover for
    // commit detail. `splits` forces uPlot to put ticks ONLY at
    // those positions; `values` returns the matching label per tick.
    const lastIdx = xs.length - 1
    const splitPositions = (() => {
      const ps = new Set([0, lastIdx])
      if (this.anchorIdx > 0 && this.anchorIdx < lastIdx) ps.add(this.anchorIdx)
      return [...ps].sort((a, b) => a - b)
    })()
    const xAxis = {
      stroke: tokens.fgSubtle,
      grid: { stroke: tokens.borderSubtle, width: 1 },
      ticks: { stroke: tokens.borderSubtle, width: 1 },
      splits: () => splitPositions,
      values: (_u, ticks) => ticks.map(t => {
        const i = Math.round(t)
        if (i === 0)            return "← older"
        if (i === lastIdx)      return "newer →"
        if (i === this.anchorIdx) return xs[i]?.sha || ""
        return ""
      }),
      font: '10px ui-monospace, "SF Mono", Menlo, monospace',
      // Leave room at the bottom for the status strip we draw in
      // the `drawAxes` hook (6px strip + 4px gap above + the label
      // text). Default size ~50; +14 covers the strip without
      // crowding.
      size: 64
    }
    const yAxis = {
      stroke: tokens.fgSubtle,
      grid: { stroke: tokens.borderSubtle, width: 1 },
      ticks: { stroke: tokens.borderSubtle, width: 1 },
      font: '10px ui-monospace, "SF Mono", Menlo, monospace'
    }

    const opts = {
      width: this.chartTarget.offsetWidth,
      height: 320,
      legend: { show: false },
      cursor: {
        x: true,
        y: false,
        focus: { prox: 30 },
        points: { size: 8, stroke: tokens.fg, fill: tokens.bgElev, width: 2 }
      },
      scales: { x: { time: false } },
      axes: [xAxis, yAxis],
      series,
      hooks: {
        // drawAxes runs once per redraw, after axes/ticks but
        // before series — perfect for the anchor marker (behind
        // the lines) and the status strip (below the plot area).
        drawAxes: [u => { this._drawAnchorMarker(u); this._drawStatusStrip(u) }],
        ready: [u => {
          u.over.style.cursor = "crosshair"
          // Capture-phase listener so we fire *before* uPlot's own
          // bubble-phase click handler (which lives on the same
          // element and may stop propagation). At click time
          // `u.cursor.idx` is whatever the last mousemove snapped
          // to — exactly what we want for "navigate to the
          // hovered point."
          u.over.addEventListener("click", () => this._handleClick(u), true)
        }]
      },
      plugins: [this._tooltipPlugin()]
    }

    this.chart = new uPlot(opts, data, this.chartTarget)
  }

  _resize() {
    if (!this.chart) return
    this.chart.setSize({ width: this.chartTarget.offsetWidth, height: 320 })
  }

  // ─── Anchor marker (vertical brand-colored line) ──────────────

  // Soft full-height vertical line at the anchor commit's X
  // position. Sits behind the data lines (we draw in drawAxes,
  // before series) so the data still reads cleanly on top.
  // Skipped when the anchor isn't inside the window (e.g. anchor
  // resolved to a commit not in `commits[]`).
  _drawAnchorMarker(u) {
    if (this.anchorIdx < 0) return
    const xs = this.payload.commits
    if (xs.length < 2) return
    const ctx = u.ctx
    const pxRatio = devicePixelRatio || 1
    const x = u.bbox.left + (this.anchorIdx / (xs.length - 1)) * u.bbox.width
    const tokens = this._readTokens()
    ctx.save()
    ctx.strokeStyle = tokens.brand
    ctx.lineWidth = 2 * pxRatio
    ctx.globalAlpha = 0.35
    ctx.beginPath()
    ctx.moveTo(x, u.bbox.top)
    ctx.lineTo(x, u.bbox.top + u.bbox.height)
    ctx.stroke()
    ctx.restore()
  }

  // ─── Status strip (drawn into the canvas after axes) ──────────

  _drawStatusStrip(u) {
    const xs = this.payload.commits
    if (!xs.length) return
    const ctx = u.ctx
    const tokens = this._readTokens()
    const pxRatio = devicePixelRatio || 1
    // bbox is in CSS px; multiply for the canvas's internal scale.
    const left = u.bbox.left
    const top  = u.bbox.top + u.bbox.height + 4 * pxRatio
    const w    = u.bbox.width
    const stripH = 6 * pxRatio
    const colW = w / xs.length

    ctx.save()
    xs.forEach((c, i) => {
      ctx.fillStyle = this._statusFill(c.status, tokens)
      // 1px gap between cells for readability
      ctx.fillRect(left + colW * i, top, Math.max(colW - 1, 1), stripH)
    })
    ctx.restore()
  }

  _statusFill(status, tokens) {
    switch (status) {
      case 0:  return tokens.success
      case 1:  return tokens.danger
      case 2:  // checksum
      case 3:  return tokens.warning
      default: return tokens.skipped
    }
  }

  // ─── Click → re-center toolbar ────────────────────────────────

  _handleClick(u) {
    const idx = u.cursor.idx
    if (idx == null) return
    const c = this.payload.commits[idx]
    if (!c) return
    const url = new URL(window.location.href)
    url.searchParams.set("center", c.sha)
    window.location.href = url.toString()
  }

  // ─── Tooltip ──────────────────────────────────────────────────

  _tooltipPlugin() {
    const tip = document.createElement("div")
    tip.className = "absolute z-30 rounded-md border border-border bg-bg-elev p-2 text-xs pointer-events-none"
    tip.style.cssText = "box-shadow: var(--shadow-card-md); width: 260px; display: none;"
    return {
      hooks: {
        ready: u => u.over.appendChild(tip),
        setCursor: u => {
          const { idx, left, top } = u.cursor
          if (idx == null || left < 0) { tip.style.display = "none"; return }
          const c = this.payload.commits[idx]
          if (!c) { tip.style.display = "none"; return }
          tip.innerHTML = this._tooltipHTML(c, idx)
          tip.style.display = ""
          // Position with a small offset; clamp so the tip doesn't
          // overflow the chart's `over` layer.
          const tipW = tip.offsetWidth
          const overW = u.over.clientWidth
          const x = Math.min(left + 12, overW - tipW - 8)
          tip.style.left = `${Math.max(8, x)}px`
          tip.style.top  = `${Math.max(8, top + 12)}px`
        }
      }
    }
  }

  _tooltipHTML(c, idx) {
    const rows = this.payload.configs.map(cfg => {
      const v = this.visibleSeries.has(cfg.key)
        ? this.payload.series[this.currentMetric]?.[cfg.key]?.[idx]
        : null
      const valText = v == null ? "—" : this._fmtNumber(v)
      return `
        <div class="flex items-center justify-between gap-2 py-0.5">
          <span class="flex items-center gap-1.5 truncate" title="${this._esc(cfg.label)}">
            <span style="display:inline-block;width:8px;height:8px;border-radius:2px;background:${cfg.color};opacity:${this.visibleSeries.has(cfg.key) ? 1 : 0.3}"></span>
            <span class="text-fg-muted truncate" style="font-size:10px">${this._esc(cfg.label)}</span>
          </span>
          <span class="font-mono tabular-nums text-fg" style="font-size:11px">${this._esc(valText)}</span>
        </div>`
    }).join("")
    const statusWord = ({0:"passing",1:"failing",2:"checksum",3:"mixed"})[c.status] || "untested"
    return `
      <div class="flex items-baseline justify-between gap-2 mb-1">
        <span class="font-mono font-semibold text-brand">${this._esc(c.sha)}</span>
        <span class="text-fg-subtle" style="font-size:10px">${this._esc(statusWord)}</span>
      </div>
      <div class="text-fg mb-1" style="font-size:11px">${this._esc(c.message || "")}</div>
      <div class="border-t border-border-subtle pt-1">${rows}</div>
      <div class="text-fg-subtle mt-1" style="font-size:10px">click to re-center</div>
    `
  }

  // ─── Theme handling ───────────────────────────────────────────

  // The theme controller flips `data-theme` on `<html>`. uPlot
  // bakes axis/grid stroke colors into the canvas at draw time;
  // those don't auto-update on token changes, so we destroy and
  // rebuild the chart whenever the attribute changes. Cheap — the
  // chart is small and rebuild is instant.
  // Charts that connect inside a `hidden` tab panel get `offsetWidth
  // === 0`, so uPlot draws a zero-width canvas. The tabs controller
  // toggles `hidden` on the panel without firing a window resize.
  // Watch the panel's `hidden` attribute and resize once it goes
  // from true → false.
  _observeVisibility() {
    const panel = this.element.closest('[data-tabs-target="panel"]')
    if (!panel) return
    this._visibilityObserver = new MutationObserver(muts => {
      for (const m of muts) {
        if (m.attributeName === "hidden" && !panel.hasAttribute("hidden")) {
          // Re-measure on the next animation frame so layout has
          // settled (offsetWidth would still be the old value
          // synchronously, on some browsers).
          requestAnimationFrame(() => this._resize())
        }
      }
    })
    this._visibilityObserver.observe(panel, { attributes: true, attributeFilter: ["hidden"] })
  }

  _observeTheme() {
    this._themeObserver = new MutationObserver(muts => {
      if (muts.some(m => m.attributeName === "data-theme")) {
        this.chart?.destroy()
        this.chart = null
        this._buildChart()
      }
    })
    this._themeObserver.observe(document.documentElement, { attributes: true })
  }

  _readTokens() {
    const cs = getComputedStyle(document.documentElement)
    const v = (n, fb) => (cs.getPropertyValue(n).trim() || fb)
    return {
      fg:            v("--color-fg",            "#1f2328"),
      fgSubtle:      v("--color-fg-subtle",     "#8b949e"),
      bgElev:        v("--color-bg-elev",       "#ffffff"),
      borderSubtle:  v("--color-border-subtle", "#e6e8ec"),
      brand:         v("--color-brand",         "#3a56fd"),
      success:       v("--color-success",       "#2da44e"),
      danger:        v("--color-danger",        "#cf222e"),
      warning:       v("--color-warning",       "#9a6700"),
      skipped:       v("--color-skipped",       "#8b949e")
    }
  }

  // ─── Utility ──────────────────────────────────────────────────

  _syncChipState() {
    this.seriesChipTargets.forEach(chip => {
      const on = this.visibleSeries.has(chip.dataset.seriesKey)
      chip.setAttribute("aria-pressed", on ? "true" : "false")
      chip.classList.toggle("opacity-40", !on)
    })
  }

  _renderEmpty(msg) {
    if (this.hasEmptyTarget) {
      this.emptyTarget.textContent = msg
      this.emptyTarget.hidden = false
    }
    if (this.hasChartTarget) this.chartTarget.hidden = true
  }

  _fmtNumber(v) {
    if (typeof v !== "number" || !isFinite(v)) return String(v)
    const abs = Math.abs(v)
    if (abs === 0) return "0"
    if (abs >= 1000) return v.toLocaleString(undefined, { maximumFractionDigits: 0 })
    if (abs >= 1)    return v.toFixed(3).replace(/\.?0+$/, "")
    return v.toPrecision(3)
  }

  _esc(s) {
    if (s == null) return ""
    return String(s).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]))
  }
}
