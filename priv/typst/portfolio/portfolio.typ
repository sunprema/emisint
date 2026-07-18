// ============================================================
// Portfolio Overview PDF Report
// Emisint APM — Academic Performance Module
// ============================================================

#set page(
  paper: "a4",
  margin: (top: 2.2cm, bottom: 2cm, left: 2.2cm, right: 2.2cm),
  header: context {
    set text(size: 7pt, fill: luma(160))
    grid(
      columns: (1fr, auto),
      align: (left, right),
      [Emisint APM — Portfolio Overview],
      [Page #counter(page).display()]
    )
    v(-4pt)
    line(length: 100%, stroke: 0.4pt + luma(210))
  }
)

#set text(size: 9pt)
#set par(leading: 1.3em)

// ============================================================
// CRITICAL: to-num must be defined before ALL other functions.
// Elixir nil arrives as the string "nil", floats may arrive as
// strings. Never check for `none` before calling to-num.
// ============================================================
#let to-num(v) = {
  if v == none or v == "nil" or v == "none" { return none }
  if type(v) == float { return v }
  if type(v) == int { return float(v) }
  if type(v) == str {
    if v.match(regex("^-?[0-9]+(\\.[0-9]+)?$")) != none {
      return float(v)
    }
  }
  none
}

#let to-bool(v) = {
  if type(v) == bool { return v }
  if type(v) == str { return v == "true" }
  false
}

#let fmt-pct(v) = {
  let n = to-num(v)
  if n == none { "—" } else { str(calc.round(n, digits: 1)) + "%" }
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

#let delta-fill(v) = {
  let n = to-num(v)
  if n == none { luma(190) }
  else if n >= 0 { rgb("#16a34a") }
  else { rgb("#dc2626") }
}

// ============================================================
// Layout helpers
// ============================================================

#let stat-box(label, value, sub-label, accent) = {
  rect(
    width: 100%,
    stroke: 0.5pt + luma(220),
    fill: luma(252),
    inset: (x: 10pt, y: 8pt)
  )[
    #text(size: 6.5pt, fill: luma(140), weight: "semibold", upper(label))
    #v(3pt)
    #grid(
      columns: (auto, auto),
      gutter: 5pt,
      align: (bottom, bottom),
      text(size: 22pt, weight: "bold", fill: accent, str(value)),
      text(size: 8.5pt, fill: luma(140), sub-label)
    )
  ]
}

#let section-rule(title, sub) = {
  v(10pt)
  rect(width: 100%, inset: (x: 8pt, y: 6pt), fill: luma(238), stroke: none)[
    #grid(
      columns: (1fr, auto),
      align: (left, right),
      text(size: 9pt, weight: "semibold", title),
      text(size: 7pt, fill: luma(120), sub)
    )
  ]
  v(6pt)
}

// delta bar for a single school row — returns 3-tuple for table spread
#let bar-row(school-name, delta, max-delta, fmt-fn) = {
  let d = to-num(delta)
  let d-color = delta-fill(delta)
  let bar-frac = if d == none or max-delta <= 0.0 { 0.0 }
                 else { calc.min(calc.abs(d) / max-delta, 1.0) }

  (
    // col 1: school name
    text(size: 7.5pt, school-name),

    // col 2: bar visualization
    block(width: 100%, height: 10pt, clip: true, {
      // track
      place(top, rect(width: 100%, height: 10pt, fill: luma(244), stroke: none))
      // center axis
      place(
        top + left, dx: 50% - 0.3pt,
        rect(width: 0.6pt, height: 10pt, fill: luma(195), stroke: none)
      )
      // delta bar
      if d != none and bar-frac > 0.0 {
        let bar-w = bar-frac * 50%
        if d >= 0 {
          place(top + left, dx: 50%,
            rect(width: bar-w, height: 10pt, fill: d-color.lighten(45%), stroke: none))
        } else {
          place(top + right, dx: -50%,
            rect(width: bar-w, height: 10pt, fill: d-color.lighten(45%), stroke: none))
        }
      }
    }),

    // col 3: delta value
    align(right, text(
      size: 7.5pt,
      weight: "semibold",
      fill: d-color,
      fmt-fn(delta)
    ))
  )
}

// ============================================================
// Scatter chart (ED% vs performance) — quadrant + regression line
// ============================================================
#let quadrant-color(q) = {
  if q == "green" { rgb("#16a34a") }
  else if q == "red" { rgb("#dc2626") }
  else { rgb("#d97706") }
}

#let scatter-chart(title, y-label, points, threshold-ed, threshold-val, slope, intercept, y-unit) = {
  let chart-h = 130pt

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

  text(size: 8pt, weight: "semibold", title)
  v(2pt)
  block(width: 100%, height: chart-h, clip: true, stroke: 0.5pt + luma(210), {
    // quadrant background fills, split at the statewide-average crosshair
    if cx != none and cy != none {
      place(top + left, rect(width: cx, height: cy, fill: rgb("#d97706").transparentize(96%), stroke: none))
      place(top + left, dx: cx, rect(width: 100% - cx, height: cy, fill: rgb("#16a34a").transparentize(96%), stroke: none))
      place(top + left, dy: cy, rect(width: cx, height: 100% - cy, fill: rgb("#dc2626").transparentize(96%), stroke: none))
      place(top + left, dx: cx, dy: cy, rect(width: 100% - cx, height: 100% - cy, fill: rgb("#d97706").transparentize(96%), stroke: none))
      place(top + left, dx: cx - 0.3pt, rect(width: 0.6pt, height: 100%, fill: luma(190), stroke: none))
      place(top + left, dy: cy - 0.3pt, rect(width: 100%, height: 0.6pt, fill: luma(190), stroke: none))
    }

    // regression trend line
    let sl = to-num(slope)
    let ic = to-num(intercept)
    if sl != none and ic != none {
      let yf0 = y-frac(sl * 0.0 + ic)
      let yf100 = y-frac(sl * 100.0 + ic)
      if yf0 != none and yf100 != none {
        place(line(
          start: (0%, (1.0 - yf0) * 100%),
          end: (100%, (1.0 - yf100) * 100%),
          stroke: 1pt + rgb("#2563eb")
        ))
      }
    }

    // data points
    for p in points {
      let xf = x-frac(p.ed_pct)
      let yf = y-frac(p.value)
      if xf != none and yf != none {
        place(
          top + left,
          dx: xf * 100% - 2.5pt,
          dy: (1.0 - yf) * 100% - 2.5pt,
          circle(radius: 2.5pt, fill: quadrant-color(p.quadrant), stroke: 0.4pt + white)
        )
      }
    }
  })
  v(3pt)
  text(size: 6pt, fill: luma(140),
    "X: Economically Disadvantaged % · Y: " + y-label + " · gray: statewide avg · blue: trend line")
}

// ============================================================
// Data bindings
// ============================================================
#let agency      = elixir_data.agency
#let school-year = elixir_data.school_year
#let mstep       = elixir_data.mstep
#let sat-data    = elixir_data.sat
#let schools-dir = elixir_data.schools
#let regression  = elixir_data.at("regression", default: none)

// ============================================================
// Page title
// ============================================================
#grid(
  columns: (1fr, auto),
  align: (left + bottom, right + bottom),
  stack(spacing: 3pt,
    text(size: 20pt, weight: "bold", agency.name),
    text(size: 10pt, fill: luma(110), "Portfolio Overview — " + school-year)
  ),
  stack(spacing: 3pt, align(right)[
    #text(size: 8pt, fill: luma(140), "Generated " + elixir_data.report_date) \
    #text(size: 8pt, fill: luma(140),
      str(agency.school_count) + " schools · Agency Code: " + str(agency.code))
  ])
)
#v(6pt)
#line(length: 100%, stroke: 1pt + luma(200))
#v(4pt)

// ============================================================
// M-STEP Section
// ============================================================
#section-rule(
  "M-STEP / PSAT — All Subjects vs. Geographic LEA",
  "Schools where school % proficient exceeds local district %"
)

// Summary cards
#let mt = to-num(mstep.total_comparable)
#let me-pct = if mt != none and mt > 0 {
  str(calc.round(to-num(mstep.exceeds) / mt * 100, digits: 0)) + "%"
} else { "—" }
#let mb-pct = if mt != none and mt > 0 {
  str(calc.round(to-num(mstep.below) / mt * 100, digits: 0)) + "%"
} else { "—" }

#grid(columns: (1fr, 1fr, 1fr), gutter: 8pt,
  stat-box("Exceeds LEA",  mstep.exceeds,  me-pct, rgb("#16a34a")),
  stat-box("Below LEA",    mstep.below,    mb-pct, rgb("#dc2626")),
  stat-box("No LEA Data",  mstep.no_data,  "",     luma(170)),
)

#v(8pt)

// Per-school bar chart
#let mstep-comparable = mstep.schools.filter(s => not to-bool(s.no_lea_found))
#let mstep-max-d = mstep-comparable.fold(0.0, (acc, s) => {
  let d = to-num(s.delta)
  if d == none { acc } else { calc.max(acc, calc.abs(d)) }
})

#if mstep-comparable.len() > 0 {
  // column header row
  grid(columns: (1fr, 2fr, 70pt), gutter: 0pt,
    text(size: 6.5pt, fill: luma(140), weight: "semibold", upper("School")),
    align(center, text(size: 6.5pt, fill: luma(140), weight: "semibold",
      upper("School vs LEA delta (pp) · best → worst"))),
    align(right, text(size: 6.5pt, fill: luma(140), weight: "semibold", upper("Delta")))
  )
  v(3pt)
  table(
    columns: (1fr, 2fr, 70pt),
    stroke: none,
    inset: (x: 4pt, y: 2.5pt),
    fill: (_, row) => if calc.odd(row) { luma(249) } else { white },
    ..mstep-comparable.map(s =>
      bar-row(s.school_name, s.delta, mstep-max-d, fmt-delta-pp)
    ).flatten()
  )
}

// Excluded schools
#if mstep.excluded.len() > 0 {
  v(8pt)
  text(size: 7pt, fill: luma(140), weight: "semibold",
    upper(str(mstep.excluded.len()) + " schools excluded — no LEA comparison available"))
  v(3pt)
  table(
    columns: (1fr, auto),
    stroke: none,
    inset: (x: 4pt, y: 2.5pt),
    fill: luma(249),
    ..mstep.excluded.map(s => (
      text(size: 7pt, fill: luma(130), s.school_name),
      text(size: 7pt, fill: luma(160), s.building_code)
    )).flatten()
  )
}

#pagebreak()

// ============================================================
// SAT Section
// ============================================================
#section-rule(
  "SAT College Readiness — All Score vs. Geographic LEA",
  "Schools where combined SAT score (Math + EBRW) exceeds local district"
)

#let st = to-num(sat-data.total_comparable)
#let se-pct = if st != none and st > 0 {
  str(calc.round(to-num(sat-data.exceeds) / st * 100, digits: 0)) + "%"
} else { "—" }
#let sb-pct = if st != none and st > 0 {
  str(calc.round(to-num(sat-data.below) / st * 100, digits: 0)) + "%"
} else { "—" }

#grid(columns: (1fr, 1fr, 1fr), gutter: 8pt,
  stat-box("Exceeds LEA",  sat-data.exceeds,  se-pct, rgb("#16a34a")),
  stat-box("Below LEA",    sat-data.below,    sb-pct, rgb("#dc2626")),
  stat-box("No LEA Data",  sat-data.no_data,  "",     luma(170)),
)

#v(8pt)

#let sat-comparable = sat-data.schools.filter(s => not to-bool(s.no_lea_found))
#let sat-max-d = sat-comparable.fold(0.0, (acc, s) => {
  let d = to-num(s.delta)
  if d == none { acc } else { calc.max(acc, calc.abs(d)) }
})

#if sat-comparable.len() > 0 {
  grid(columns: (1fr, 2fr, 70pt), gutter: 0pt,
    text(size: 6.5pt, fill: luma(140), weight: "semibold", upper("School")),
    align(center, text(size: 6.5pt, fill: luma(140), weight: "semibold",
      upper("School vs LEA delta (pts) · best → worst"))),
    align(right, text(size: 6.5pt, fill: luma(140), weight: "semibold", upper("Delta")))
  )
  v(3pt)
  table(
    columns: (1fr, 2fr, 70pt),
    stroke: none,
    inset: (x: 4pt, y: 2.5pt),
    fill: (_, row) => if calc.odd(row) { luma(249) } else { white },
    ..sat-comparable.map(s =>
      bar-row(s.school_name, s.delta, sat-max-d, fmt-delta-pts)
    ).flatten()
  )
}

#if sat-data.excluded.len() > 0 {
  v(8pt)
  text(size: 7pt, fill: luma(140), weight: "semibold",
    upper(str(sat-data.excluded.len()) + " schools excluded — no SAT comparison available"))
  v(3pt)
  table(
    columns: (1fr, auto, 1fr),
    stroke: none,
    inset: (x: 4pt, y: 2.5pt),
    fill: luma(249),
    ..sat-data.excluded.map(s => (
      text(size: 7pt, fill: luma(130), s.school_name),
      text(size: 7pt, fill: luma(160), s.building_code),
      text(size: 7pt, fill: luma(160), s.exclusion_reason)
    )).flatten()
  )
}

// ============================================================
// ED% vs Performance Regression
// ============================================================
#if regression != none {
  pagebreak()
  section-rule(
    "Economically Disadvantaged % vs. Performance",
    "Green: beating the odds · Yellow: as expected · Red: underperforming despite advantage"
  )
  v(6pt)
  grid(columns: (1fr, 1fr), gutter: 14pt,
    scatter-chart(
      "M-STEP vs. ED%", "M-STEP Proficiency %",
      regression.mstep.points, regression.mstep.threshold_ed_pct, regression.mstep.threshold_value,
      regression.mstep.slope, regression.mstep.intercept, regression.mstep.y_unit
    ),
    scatter-chart(
      "SAT vs. ED%", "SAT Score",
      regression.sat.points, regression.sat.threshold_ed_pct, regression.sat.threshold_value,
      regression.sat.slope, regression.sat.intercept, regression.sat.y_unit
    )
  )
  v(4pt)
  text(size: 6.5pt, fill: luma(140),
    str(int(to-num(regression.mstep.excluded_count))) + " schools excluded from the M-STEP chart, " +
    str(int(to-num(regression.sat.excluded_count))) + " from the SAT chart — missing ED% or performance data.")
}

// ============================================================
// School Directory
// ============================================================
#pagebreak(weak: true)
#section-rule("School Directory", str(schools-dir.len()) + " Open-Active schools")

#table(
  columns: (1fr, 70pt, 80pt, 60pt),
  stroke: (x, y) => if y == 0 { (bottom: 0.5pt + luma(180)) } else { none },
  inset: (x: 5pt, y: 4pt),
  fill: (_, row) => if row == 0 { luma(238) } else if calc.odd(row) { luma(249) } else { white },
  // Header
  text(size: 7.5pt, weight: "semibold", "School"),
  text(size: 7.5pt, weight: "semibold", "District Code"),
  text(size: 7.5pt, weight: "semibold", "County"),
  text(size: 7.5pt, weight: "semibold", "Grades"),
  // Rows
  ..schools-dir.map(s => (
    text(size: 7.5pt, s.name),
    text(size: 7.5pt, fill: luma(110), if s.district_code == "nil" or s.district_code == none { "—" } else { s.district_code }),
    text(size: 7.5pt, fill: luma(110), if s.county == "nil" or s.county == none { "—" } else { s.county }),
    text(size: 7.5pt, fill: luma(110), if s.grades == "nil" or s.grades == none { "—" } else { s.grades })
  )).flatten()
)
