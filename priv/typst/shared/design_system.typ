// Emisint — shared Typst design-system partial
//
// Single source of truth for color tokens, coercion helpers, and reusable
// components used across the PDF report templates in priv/typst/school/
// and priv/typst/portfolio/. Import via:
//
//   #import "/shared/design_system.typ": *
//
// (requires `root_directory` in Imprintor.Config to point at priv/typst/,
// so the leading "/" resolves there — see any `*_pdf.ex` report module.)
//
// `comprehensive.typ` is an intentionally-orphaned prototype (no Elixir
// loader/route wires it up) and is NOT migrated to this partial — see
// PLAN_betterPDF.md Phase 0 notes.

// ── Color tokens ──────────────────────────────────────────────────────────
// Brand/page-chrome colors (headers, title bars, table chrome) — carried
// over verbatim from the reference "School Performance Report" design.
#let c-primary   = rgb("#0b3d78") // deep brand navy — headers, title bars, page strip
#let c-accent    = rgb("#2563eb") // brand blue — this-school series, links, accents
#let c-accent-bg = rgb("#eff6ff")
#let c-text      = rgb("#1e293b")
#let c-muted     = rgb("#64748b")
#let c-border    = rgb("#e2e8f0")
#let c-row-alt   = rgb("#f8fafc")
#let c-th-bg     = rgb("#f1f5f9")

// Semantic status colors (good/caution/bad), converted from this app's
// actual live DaisyUI theme (success/warning/error light-mode OKLCH values
// in assets/css/app.css) so a PDF's "Exceeds Standard" pill, proficiency
// badges, and the ED%-vs-performance regression quadrants read as the same
// visual language as the dashboard — not an independently-chosen PDF palette.
#let c-success    = rgb("#009689")
#let c-success-bg = rgb("#e3f6f4")
#let c-warning    = rgb("#df6f00")
#let c-warning-bg = rgb("#fdf1e2")
#let c-error      = rgb("#ea003e")
#let c-error-bg   = rgb("#fde7ed")

// Comparison-series role aliases — name a chart series by its *role*
// (this school vs. its comparator) rather than repeating literal colors,
// so every template's "who is blue / who is green" question has one answer.
#let c-school = c-accent
#let c-peer   = c-success
#let c-lea    = c-warning
#let c-top    = c-success
#let c-all    = c-warning
#let c-state  = c-muted

// ── Coercion helpers (see .claude/skills/typst/SKILL.md) ─────────────────
// Elixir `nil` arrives as the *string* "nil" (an Imprintor/Rust NIF
// behavior, not fixable from Typst) — never compare a raw value to `none`
// before piping it through `to-num`.
#let to-num(v) = {
  if v == none { none }
  else if type(v) == str {
    let t = v.trim()
    if t == "nil" or t == "none" or t == "" or t == "N/A" { none }
    else { float(t) }
  } else if type(v) == bool { none }
  else { float(v) }
}

#let to-bool(v) = {
  if type(v) == bool { v }
  else if type(v) == str { v == "true" }
  else { false }
}

// Displays a string value from Elixir, collapsing the nil-string and Typst
// `none` cases to "".
#let disp-str(v) = {
  if v == none { "" }
  else if type(v) == str {
    let t = v.trim()
    if t == "nil" { "" } else { v }
  } else { v }
}

// ── Formatting helpers ────────────────────────────────────────────────────
#let fmt1(v) = {
  let n = to-num(v)
  if n == none { "—" } else { str(calc.round(n, digits: 1)) }
}

#let fmt-pct(v) = {
  let n = to-num(v)
  if n == none { "—" } else { str(calc.round(n, digits: 1)) + "%" }
}

#let fmt-int(v) = {
  let n = to-num(v)
  if n == none { "—" } else { str(int(n)) }
}

#let fmt-delta-pp(v) = {
  let n = to-num(v)
  if n == none { "—" }
  else if n >= 0 { "+" + str(calc.round(n, digits: 1)) + " pp" }
  else { str(calc.round(n, digits: 1)) + " pp" }
}

#let fmt-delta-pts(v) = {
  let n = to-num(v)
  if n == none { "—" }
  else if n >= 0 { "+" + str(calc.round(n, digits: 1)) + " pts" }
  else { str(calc.round(n, digits: 1)) + " pts" }
}

// ── Text / section components ────────────────────────────────────────────
#let th(t) = table.cell(
  fill: c-th-bg,
  text(weight: "bold", size: 8pt, fill: c-muted, upper(t))
)

// Centered brand-blue section heading — the School Performance Report /
// Regression Report family's style.
#let section-heading(title, subtitle: none) = {
  v(10pt)
  align(center, {
    text(weight: "bold", size: 12pt, fill: c-primary, title)
    if subtitle != none and subtitle != "" {
      linebreak()
      v(2pt)
      text(size: 8.5pt, fill: c-muted, subtitle)
    }
  })
  v(8pt)
}

// Left red-accent-bar section title — the comparison-report family's style
// (School vs LEA, SSS Comparison, CRD Comparison).
#let section-title(title, subtitle: "") = {
  v(18pt)
  grid(
    columns: (4pt, 1fr),
    gutter: 10pt,
    rect(width: 4pt, height: if subtitle != "" { 32pt } else { 22pt }, fill: c-error, radius: 1pt),
    {
      text(weight: "bold", size: 11pt, fill: c-text, title)
      if subtitle != "" {
        linebreak()
        text(size: 8.5pt, fill: c-muted, subtitle)
      }
    }
  )
  v(8pt)
}

// KPI stat box: big number + label + optional sub-label, in an accent color.
#let stat-box(label, value, sub: "", accent: c-accent) = rect(
  width: 100%,
  inset: (x: 14pt, y: 12pt),
  stroke: 0.75pt + c-border,
  radius: 2pt,
  {
    text(size: 8pt, fill: c-muted, upper(label))
    v(4pt)
    text(size: 22pt, weight: "bold", fill: accent, value)
    if sub != "" { linebreak(); text(size: 7.5pt, fill: c-muted, sub) }
  }
)

// MDE entity detail row: label cell + value cell (none/"nil"/"" → em dash).
#let detail-row(label, value, label-width: 150pt) = {
  let empty = value == none or value == "" or (type(value) == str and value.trim() == "nil")
  grid(
    columns: (label-width, 1fr),
    gutter: 0pt,
    rect(width: 100%, inset: (x: 10pt, y: 7pt),
      stroke: (bottom: 0.5pt + c-border, right: 0.5pt + c-border), fill: c-th-bg,
      text(size: 8pt, weight: "bold", fill: c-muted, upper(label))),
    rect(width: 100%, inset: (x: 10pt, y: 7pt), stroke: (bottom: 0.5pt + c-border),
      if empty { text(fill: c-muted, style: "italic", "—") }
      else { text(size: 9pt, fill: c-text, value) })
  )
}

// ── Badges ────────────────────────────────────────────────────────────────

// Small coloured score badge ("X.X%" or "X.X"); none → muted dash.
#let mini-badge(v, fg, bg, suffix: "%") = {
  let n = to-num(v)
  if n == none {
    box(fill: c-row-alt, inset: (x: 6pt, y: 2pt), radius: 3pt,
      text(fill: c-muted, weight: "bold", size: 8pt, "—"))
  } else {
    box(fill: bg, inset: (x: 6pt, y: 2pt), radius: 3pt,
      text(fill: fg, weight: "bold", size: 8pt, str(calc.round(n, digits: 1)) + suffix))
  }
}

// Threshold-colored proficiency badge (value 0-100). `approximate: true`
// marks a Rule-2 range approximation (FERPA suppression) with a "*" suffix
// and a neutral gray background instead of a rating color.
#let pct-badge(v, approximate: false) = {
  let approximate = to-bool(approximate)
  let n = to-num(v)
  if n == none {
    box(fill: c-row-alt, inset: (x: 7pt, y: 3pt), radius: 3pt,
      text(fill: c-muted, weight: "bold", size: 8.5pt, "—"))
  } else {
    let (bg, fg) = if approximate { (luma(220), rgb("#555555")) }
      else if n >= 60 { (c-success-bg, c-success) }
      else if n >= 40 { (c-warning-bg, c-warning) }
      else { (c-error-bg, c-error) }
    let label = str(calc.round(n, digits: 1)) + "%" + if approximate { "*" } else { "" }
    box(fill: bg, inset: (x: 7pt, y: 3pt), radius: 3pt,
      text(fill: fg, weight: "bold", size: 8.5pt, label))
  }
}

// Score cell (no badge chrome, just colorless numeric text): none → dash.
#let score-cell(v) = {
  let n = to-num(v)
  if n == none { text(fill: c-muted, "—") } else { [#calc.round(n, digits: 1)] }
}

// Delta badge for an already-computed delta value. Coerces BEFORE checking
// for `none` (see SKILL.md's "nil-string trap") — the previous per-template
// copy of this in school_vs_lea.typ checked `v == none` first, which never
// caught Elixir `nil` (it arrives as the string "nil"), and crashed Typst
// compilation ("cannot compare none and integer") whenever a subject/grade
// cell had no LEA comparison. Fixed here; see PLAN_betterPDF.md.
#let delta-badge(v, suffix: " pts") = {
  let n = to-num(v)
  if n == none {
    box(fill: c-row-alt, inset: (x: 6pt, y: 3pt), radius: 3pt, text(fill: c-muted, size: 8pt, "—"))
  } else {
    let d = calc.round(n, digits: 1)
    let (bg, fg) = if d >= 0 { (c-success-bg, c-success) } else { (c-error-bg, c-error) }
    let lbl = (if d >= 0 { "+" } else { "" }) + str(d) + suffix
    box(fill: bg, inset: (x: 6pt, y: 3pt), radius: 3pt, text(fill: fg, weight: "bold", size: 8pt, lbl))
  }
}

// Delta badge computed between two raw values (school vs. a comparator).
#let delta-badge-between(school, other, suffix: " pts") = {
  let s = to-num(school)
  let o = to-num(other)
  if s == none or o == none {
    box(fill: c-row-alt, inset: (x: 6pt, y: 2pt), radius: 3pt, text(fill: c-muted, size: 7.5pt, "—"))
  } else {
    delta-badge(s - o, suffix: suffix)
  }
}

// SGP badge — colour-coded by the standard growth bands (>=50 strong,
// 40-49 typical, <40 below); value is on the native 1-99 SGP scale.
#let sgp-badge(v) = {
  let n = to-num(v)
  if n == none {
    box(fill: c-row-alt, inset: (x: 6pt, y: 3pt), radius: 3pt,
      text(fill: c-muted, size: 8pt, "—"))
  } else {
    let (bg, fg) = if n >= 50 { (c-success-bg, c-success) }
      else if n >= 40 { (c-warning-bg, c-warning) }
      else { (c-error-bg, c-error) }
    box(fill: bg, inset: (x: 6pt, y: 3pt), radius: 3pt,
      text(fill: fg, weight: "bold", size: 8pt, str(calc.round(n, digits: 1))))
  }
}

// Bright pill for categorical ratings ("Exceeds Standard", etc.) — the
// School Performance Report's contract-status pills.
#let rating-label(r) = {
  if r == "exceeds" { "Exceeds Standard" }
  else if r == "meets" { "Meets Standard" }
  else if r == "approaching" { "Approaching Standard" }
  else if r == "below" { "Does Not Meet Standard" }
  else { "Insufficient Data" }
}

#let status-pill(r) = {
  let (bg, fg) = if r == "exceeds" or r == "meets" { (c-success-bg, c-success) }
    else if r == "approaching" { (c-warning-bg, c-warning) }
    else if r == "below" { (c-error-bg, c-error) }
    else { (c-th-bg, c-muted) }
  box(fill: bg, inset: (x: 10pt, y: 5pt), radius: 10pt,
    text(fill: fg, weight: "bold", size: 8.5pt, rating-label(r)))
}

// ── Quadrant classification (ED% vs performance regression) ──────────────
// Matches `EmisintWeb.Components.ScatterChart`'s green/warning/red quadrant
// coloring (see PLAN_betterPDF.md Phase 0.3 decision) so a school's
// "beating the odds" classification looks the same on the live dashboard
// and in a downloaded PDF.
#let quadrant-color(q) = {
  if q == "green" { c-success }
  else if q == "red" { c-error }
  else { c-warning }
}

#let quadrant-label(q) = {
  if q == "green" { "Beating the Odds" }
  else if q == "red" { "Underperforming" }
  else { "As Expected" }
}

#let quadrant-badge(q) = {
  let (bg, fg) = if q == "green" { (c-success-bg, c-success) }
    else if q == "red" { (c-error-bg, c-error) }
    else { (c-warning-bg, c-warning) }
  box(fill: bg, inset: (x: 7pt, y: 3pt), radius: 10pt,
    text(fill: fg, weight: "bold", size: 7.5pt, quadrant-label(q)))
}

// Sorts by performance (best first) and assigns a stable #1..N index — used
// to number chart dots so they cross-reference a supporting-data table
// (PDFs can't do hover tooltips, so this is the static equivalent).
#let with-index(points) = {
  points.sorted(key: p => -(to-num(p.value))).enumerate().map(((i, p)) => p + (idx: i + 1))
}

// ED% (x) vs. performance (y) scatter chart with a statewide-average
// crosshair and a least-squares trend line. `numbered: true` labels each
// dot with its `idx` (set via `with-index`) to cross-reference a table;
// leave `false` for a compact chart with no supporting table alongside it.
#let regression-chart(
  y-label, points, threshold-ed, threshold-val, slope, intercept, y-unit,
  chart-h: 130pt, numbered: false, dot-radius: 3.5pt
) = {
  let y-min = 0.0
  let y-max = 100.0
  if y-unit == "score" {
    let vals = points.map(p => to-num(p.value)).filter(v => v != none)
    let t = to-num(threshold-val)
    let all-vals = if t != none { vals + (t,) } else { vals }
    if all-vals.len() > 0 {
      let mn = calc.min(..all-vals)
      let mx = calc.max(..all-vals)
      let pad = calc.max((mx - mn) * 0.15, 20.0)
      y-min = calc.floor(mn - pad)
      y-max = calc.ceil(mx + pad)
    } else {
      y-min = 400.0
      y-max = 1600.0
    }
  }

  let x-frac(v) = {
    let n = to-num(v)
    if n == none { none } else { calc.min(calc.max(n / 100.0, 0.0), 1.0) }
  }
  let y-frac(v) = {
    let n = to-num(v)
    if n == none { none } else { calc.min(calc.max((n - y-min) / (y-max - y-min), 0.0), 1.0) }
  }

  let cx-frac = x-frac(threshold-ed)
  let cy-frac = y-frac(threshold-val)
  let cx = if cx-frac != none { cx-frac * 100% }
  let cy = if cy-frac != none { (1.0 - cy-frac) * 100% }

  block(width: 100%, height: chart-h, clip: true, stroke: 0.5pt + c-border, {
    if cx != none and cy != none {
      place(top + left, rect(width: cx, height: cy, fill: c-warning.transparentize(96%), stroke: none))
      place(top + left, dx: cx, rect(width: 100% - cx, height: cy, fill: c-success.transparentize(96%), stroke: none))
      place(top + left, dy: cy, rect(width: cx, height: 100% - cy, fill: c-error.transparentize(96%), stroke: none))
      place(top + left, dx: cx, dy: cy, rect(width: 100% - cx, height: 100% - cy, fill: c-warning.transparentize(96%), stroke: none))
      place(top + left, dx: cx - 0.3pt, rect(width: 0.6pt, height: 100%, fill: luma(190), stroke: none))
      place(top + left, dy: cy - 0.3pt, rect(width: 100%, height: 0.6pt, fill: luma(190), stroke: none))
    }

    let sl = to-num(slope)
    let ic = to-num(intercept)
    if sl != none and ic != none {
      let yf0 = y-frac(sl * 0.0 + ic)
      let yf100 = y-frac(sl * 100.0 + ic)
      if yf0 != none and yf100 != none {
        place(line(
          start: (0%, (1.0 - yf0) * 100%),
          end: (100%, (1.0 - yf100) * 100%),
          stroke: 1.3pt + c-primary
        ))
      }
    }

    for p in points {
      let xf = x-frac(p.ed_pct)
      let yf = y-frac(p.value)
      if xf != none and yf != none {
        let cx = xf * 100%
        let cy = (1.0 - yf) * 100%
        place(top + left, dx: cx - dot-radius, dy: cy - dot-radius,
          circle(radius: dot-radius, fill: quadrant-color(p.quadrant), stroke: 0.4pt + white))
        if numbered {
          let label = text(size: 5.5pt, weight: "bold", fill: white, str(p.idx))
          context {
            let sz = measure(label)
            place(top + left, dx: cx - sz.width / 2, dy: cy - sz.height / 2, label)
          }
        }
      }
    }
  })
}

// ── Arc geometry (pie charts / gauges via polygon fill) ──────────────────
// Angle measured clockwise from 12 o'clock. Returns a point list usable
// with `polygon(fill: .., ..pts)`, already offset into a 0..2*radius box frame.
#let arc-points(radius, start, sweep, steps: 60) = {
  let pts = ((radius, radius),)
  for i in range(steps + 1) {
    let a = start + sweep * (i / steps)
    let x = radius + radius * calc.sin(a)
    let y = radius - radius * calc.cos(a)
    pts = pts + ((x, y),)
  }
  pts
}

// Donut/pie chart from a list of (name, pct, color) slices, with a legend.
#let pie-chart(slices, radius: 46pt, inner: 0.55) = {
  let size = radius * 2
  box(width: size, height: size, {
    let cursor = 0deg
    for s in slices {
      let pct = to-num(s.pct)
      if pct != none and pct > 0 {
        let sweep = 360deg * pct / 100
        place(top + left, polygon(fill: s.color, ..arc-points(radius, cursor, sweep)))
        cursor = cursor + sweep
      }
    }
    place(center + horizon, circle(radius: radius * inner, fill: white))
  })
}

#let pie-legend(slices) = {
  for s in slices {
    grid(columns: (8pt, auto), gutter: 5pt, align: horizon,
      box(width: 8pt, height: 8pt, fill: s.color, radius: 1pt),
      text(size: 8pt, fill: c-text, disp-str(s.name) + "  " + fmt-pct(s.pct))
    )
    v(3pt)
  }
}

// Circular gauge: colored progress ring over a gray track, value centered.
#let gauge(value, max, color, size: 92pt) = {
  let radius = size / 2
  let n = to-num(value)
  let pct = if n == none { 0.0 } else { calc.min(calc.max(n / max, 0.0), 1.0) }
  box(width: size, height: size, {
    place(top + left, polygon(fill: c-border, ..arc-points(radius, 0deg, 360deg)))
    if pct > 0 {
      place(top + left, polygon(fill: color, ..arc-points(radius, 0deg, 360deg * pct)))
    }
    place(center + horizon, circle(radius: radius * 0.62, fill: white))
    place(center + horizon, text(weight: "bold", size: 16pt, fill: c-text, fmt1(value)))
  })
}

// Horizontal bar list — one bar per {label, pct}.
#let horizontal-bars(items, color: c-accent, max: 100.0) = {
  for it in items {
    let n = to-num(it.pct)
    let frac = if n == none { 0.0 } else { calc.min(n / max, 1.0) }
    grid(columns: (1fr, 1.6fr, auto), gutter: 6pt, align: horizon,
      text(size: 8pt, fill: c-muted, disp-str(it.label)),
      block(height: 9pt, width: 100%, {
        grid(columns: (frac * 100% + 0.01%, 1fr), rows: 9pt,
          rect(width: 100%, height: 100%, fill: color,
            radius: (left: 2pt, right: if frac >= 0.99 { 2pt } else { 0pt })),
          rect(width: 100%, height: 100%, fill: c-border, radius: (right: 2pt)))
      }),
      text(size: 8pt, weight: "bold", fill: c-text, fmt-pct(it.pct))
    )
    v(5pt)
  }
}

// Multi-series line chart. `series` is a list of {name, color, points}
// where each point is {year, value}. All series share an x-axis (years of
// the first series) and an auto-scaled y-axis.
#let line-chart(series, height: 110pt) = {
  let all-vals = ()
  for s in series {
    for p in s.points {
      let n = to-num(p.value)
      if n != none { all-vals = all-vals + (n,) }
    }
  }
  let y-min = if all-vals.len() > 0 { calc.min(..all-vals) } else { 0.0 }
  let y-max = if all-vals.len() > 0 { calc.max(..all-vals) } else { 100.0 }
  let pad = calc.max((y-max - y-min) * 0.2, 2.0)
  let y-min = y-min - pad
  let y-max = y-max + pad
  let span = if y-max - y-min == 0 { 1.0 } else { y-max - y-min }

  let years = series.at(0).points.map(p => disp-str(p.year))
  let n-pts = years.len()

  let x-frac(i) = if n-pts <= 1 { 0.0 } else { i / (n-pts - 1) }
  let y-frac(v) = {
    let n = to-num(v)
    if n == none { none } else { (n - y-min) / span }
  }

  block(width: 100%, height: height, clip: true, stroke: 0.5pt + c-border, {
    if y-min < 0 and y-max > 0 {
      let zf = y-frac(0.0)
      place(top + left, dy: (1.0 - zf) * 100%,
        line(start: (0%, 0%), end: (100%, 0%), stroke: 0.5pt + c-border))
    }
    for s in series {
      let pts = s.points
      for i in range(n-pts - 1) {
        let yf0 = y-frac(pts.at(i).value)
        let yf1 = y-frac(pts.at(i + 1).value)
        if yf0 != none and yf1 != none {
          place(line(
            start: (x-frac(i) * 100%, (1.0 - yf0) * 100%),
            end: (x-frac(i + 1) * 100% , (1.0 - yf1) * 100%),
            stroke: 1.3pt + s.color
          ))
        }
      }
      for i in range(n-pts) {
        let yf = y-frac(pts.at(i).value)
        if yf != none {
          place(top + left,
            dx: x-frac(i) * 100% - 2.2pt, dy: (1.0 - yf) * 100% - 2.2pt,
            circle(radius: 2.2pt, fill: s.color, stroke: 0.4pt + white))
        }
      }
    }
  })
  v(2pt)
  grid(columns: (1fr,) * n-pts,
    ..years.map(y => align(center, text(size: 6.5pt, fill: c-muted, y)))
  )
}

#let chart-legend(series) = {
  for s in series {
    box(inset: (right: 12pt), {
      box(width: 8pt, height: 8pt, fill: s.color, radius: 1pt)
      h(4pt)
      text(size: 8pt, fill: c-muted, s.name)
    })
  }
}

// Heatmap-style grade-by-year table: darker blue = higher value.
#let heatmap-table(years, rows, totals) = {
  let all-vals = ()
  for r in rows {
    for v in r.values {
      let n = to-num(v)
      if n != none { all-vals = all-vals + (n,) }
    }
  }
  let mx = if all-vals.len() > 0 { calc.max(..all-vals) } else { 1.0 }
  let mn = if all-vals.len() > 0 { calc.min(..all-vals) } else { 0.0 }
  let span = if mx - mn == 0 { 1.0 } else { mx - mn }

  let cell(v) = {
    let n = to-num(v)
    if n == none {
      table.cell(fill: c-row-alt, align(center, text(size: 7.5pt, fill: c-muted, "—")))
    } else {
      let t = (n - mn) / span
      let bg = c-accent-bg.mix((c-primary, t * 100%))
      let fg = if t > 0.55 { white } else { c-text }
      table.cell(fill: bg, align(center, text(size: 7.5pt, weight: "bold", fill: fg, str(int(n)))))
    }
  }

  table(
    columns: (1.1fr,) + (1fr,) * years.len(),
    stroke: 0.4pt + c-border,
    inset: (x: 6pt, y: 3.2pt),
    th("Grade"), ..years.map(y => th(y)),
    ..rows.map(r => (
      table.cell(fill: c-th-bg, text(size: 8pt, weight: "bold", "Grade " + disp-str(r.grade))),
      ..r.values.map(cell)
    )).flatten(),
    table.cell(fill: c-primary, text(fill: white, weight: "bold", size: 8pt, "Total")),
    ..totals.map(t => table.cell(fill: c-primary, align(center,
      text(fill: white, weight: "bold", size: 8pt, str(int(to-num(t)))))))
  )
}

// Branded decorative divider used in place of a per-school campus photo — a
// real photo isn't realistic to source for every school. Renders the
// school's initials as a large, faint monogram over a brand-blue gradient.
#let monogram(name) = {
  let stopwords = ("the", "of", "and", "&", "a", "an", "for")
  let words = name
    .split(" ")
    .map(w => w.trim())
    .filter(w => w != "" and lower(w) not in stopwords)
  if words.len() == 0 { "" }
  else { words.slice(0, calc.min(3, words.len())).map(w => upper(w.slice(0, 1))).join("") }
}

#let decorative-band(name, height: 90pt) = rect(
  width: 100%, height: height, radius: 2pt,
  fill: gradient.linear(c-primary, c-accent, angle: 45deg),
  align(center + horizon,
    text(fill: white.transparentize(72%), weight: "bold", size: height * 0.55,
      monogram(disp-str(name))))
)
