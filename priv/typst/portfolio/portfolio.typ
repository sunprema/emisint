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
// Data bindings
// ============================================================
#let agency      = elixir_data.agency
#let school-year = elixir_data.school_year
#let mstep       = elixir_data.mstep
#let sat-data    = elixir_data.sat
#let schools-dir = elixir_data.schools

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
