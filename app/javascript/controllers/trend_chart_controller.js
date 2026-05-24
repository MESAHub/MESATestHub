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
    this.currentMetric = this.payload.default_metric
    this.visibleSeries = new Set(this.payload.configs.map(c => c.key))
    this._buildChart()
    this._observeTheme()
    this._onResize = () => this._resize()
    window.addEventListener("resize", this._onResize)
  }

  disconnect() {
    window.removeEventListener("resize", this._onResize)
    if (this._themeObserver) this._themeObserver.disconnect()
    if (this.chart) { this.chart.destroy(); this.chart = null }
  }

  // ─── User interactions ────────────────────────────────────────

  selectMetric(event) {
    this.currentMetric = event.currentTarget.value
    this._updateData()
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
    const xAxis = {
      stroke: tokens.fgSubtle,
      grid: { stroke: tokens.borderSubtle, width: 1 },
      ticks: { stroke: tokens.borderSubtle, width: 1 },
      // Show ~6 short-SHA labels evenly across the axis. uPlot
      // calls `values()` with the auto-computed ticks; we override
      // each to the commit SHA at that integer index.
      values: (_u, ticks) => ticks.map(t => {
        const i = Math.round(t)
        return xs[i] ? xs[i].sha : ""
      }),
      space: 60,
      font: '10px ui-monospace, "SF Mono", Menlo, monospace',
      // Leave room at the bottom for the status strip we draw in
      // the `drawAxes` hook (6px strip + 4px gap above + 14px for
      // the SHA label below). Default size ~50; +14 covers the
      // strip without crowding.
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
        drawAxes: [u => this._drawStatusStrip(u)],
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
