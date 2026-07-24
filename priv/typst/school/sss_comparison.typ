// Emisint — Statistically Similar Schools (SSS) Comparison Report

#let c-red      = rgb("#b91c1c")
#let c-red-bg   = rgb("#fef2f2")
#let c-blue     = rgb("#1d4ed8")
#let c-blue-bg  = rgb("#eff6ff")
#let c-green    = rgb("#15803d")
#let c-green-bg = rgb("#f0fdf4")
#let c-amber    = rgb("#b45309")
#let c-amber-bg = rgb("#fffbeb")
#let c-text     = rgb("#1e293b")
#let c-muted    = rgb("#64748b")
#let c-border   = rgb("#e2e8f0")
#let c-row-alt  = rgb("#f8fafc")
#let c-th-bg    = rgb("#f1f5f9")
#let c-school   = rgb("#1d4ed8")
#let c-peer     = rgb("#15803d")

#set page(
  paper: "us-letter",
  margin: (top: 0.85in, bottom: 0.85in, left: 0.85in, right: 0.85in),
  header: context {
    if counter(page).get().first() > 1 [
      #set text(size: 8pt, fill: c-muted, font: "Helvetica Neue")
      #grid(
        columns: (1fr, auto),
        align: (horizon + left, horizon + right),
        [#elixir_data.school.name #h(6pt) #text(fill: c-border, "│") #h(6pt) SSS Comparison],
        [Page #counter(page).display()]
      )
      #v(3pt)
      #line(length: 100%, stroke: 0.5pt + c-border)
    ]
  },
  footer: context {
    set text(size: 7.5pt, fill: c-muted, font: "Helvetica Neue")
    line(length: 100%, stroke: 0.5pt + c-border)
    v(3pt)
    grid(
      columns: (1fr, auto),
      align: (horizon + left, horizon + right),
      [Confidential — Emisint Academic Performance Module],
      [Generated #elixir_data.school.report_date]
    )
  }
)

#set text(font: "Helvetica Neue", size: 9.5pt, fill: c-text)
#set par(leading: 0.6em, spacing: 0.6em)

#let to-num(v) = {
  if v == none { none }
  else if type(v) == str {
    let t = v.trim()
    if t == "nil" or t == "" or t == "N/A" { none } else { float(t) }
  } else { float(v) }
}

#let truthy(v) = if type(v) == str { v == "true" } else { v == true }

#let th(t) = table.cell(fill: c-th-bg, text(weight: "bold", size: 8pt, fill: c-muted, upper(t)))

#let section-title(title, subtitle: "") = {
  v(18pt)
  grid(
    columns: (4pt, 1fr),
    gutter: 10pt,
    rect(width: 4pt, height: if subtitle != "" { 32pt } else { 22pt }, fill: c-red, radius: 1pt),
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

#let pct-badge(v) = {
  let n = to-num(v)
  if n == none {
    box(fill: c-row-alt, inset: (x: 7pt, y: 3pt), radius: 3pt,
      text(fill: c-muted, weight: "bold", size: 8.5pt, "—"))
  } else {
    let (bg, fg) = if n >= 60 { (c-green-bg, c-green) }
                   else if n >= 40 { (c-amber-bg, c-amber) }
                   else { (c-red-bg, c-red) }
    box(fill: bg, inset: (x: 7pt, y: 3pt), radius: 3pt,
      text(fill: fg, weight: "bold", size: 8.5pt, str(calc.round(n, digits: 1)) + "%"))
  }
}

#let score-cell(v) = {
  let n = to-num(v)
  if n == none { text(fill: c-muted, "—") } else { [#calc.round(n, digits: 1)] }
}

#let delta-badge(school, other, suffix: " pts") = {
  let s = to-num(school)
  let o = to-num(other)
  if s == none or o == none {
    box(fill: c-row-alt, inset: (x: 6pt, y: 2pt), radius: 3pt, text(fill: c-muted, size: 7.5pt, "—"))
  } else {
    let d = calc.round(s - o, digits: 1)
    let (bg, fg) = if d >= 0 { (c-green-bg, c-green) } else { (c-red-bg, c-red) }
    let lbl = (if d >= 0 { "+" } else { "" }) + str(d) + suffix
    box(fill: bg, inset: (x: 6pt, y: 2pt), radius: 3pt, text(fill: fg, weight: "bold", size: 7.5pt, lbl))
  }
}

#let bi-bar(school, peer, max-val) = {
  let s = to-num(school)
  let p = to-num(peer)
  let sp  = if s != none { calc.min(s / max-val, 1.0) } else { 0.0 }
  let pp  = if p != none { calc.min(p / max-val, 1.0) } else { 0.0 }
  let bar(pct, col) = grid(
    columns: (pct * 100% + 0.01%, 1fr),
    rows: 7pt,
    rect(width: 100%, height: 100%, fill: col,
      radius: (left: 2pt, right: if pct >= 0.99 { 2pt } else { 0pt })),
    rect(width: 100%, height: 100%, fill: c-border, radius: (right: 2pt))
  )
  block(width: 100%, { bar(sp, c-school); v(2pt); bar(pp, c-peer) })
}

#let compare-row(label, school, peer, max-val, pct: true) = {
  let suf = if pct { "%" } else { "" }
  block(width: 100%, spacing: 0pt, breakable: false, {
    grid(
      columns: (1fr, auto, auto),
      gutter: 6pt,
      align: (left + horizon, right + horizon, right + horizon),
      text(size: 9pt, weight: "semibold", label),
      mini-badge(peer, c-peer, c-green-bg, suffix: suf),
      mini-badge(school, c-school, c-blue-bg, suffix: suf),
    )
    v(5pt)
    bi-bar(school, peer, max-val)
    v(4pt)
    grid(
      columns: (1fr, auto),
      gutter: 8pt,
      align: (left, right),
      [],
      { text(size: 7pt, fill: c-muted, "vs SSS "); delta-badge(school, peer) },
    )
    v(10pt)
  })
}

#let detail-row(label, value) = {
  let empty = value == none or value == "" or (type(value) == str and value.trim() == "nil")
  grid(
    columns: (150pt, 1fr),
    gutter: 0pt,
    rect(width: 100%, inset: (x: 10pt, y: 7pt),
      stroke: (bottom: 0.5pt + c-border, right: 0.5pt + c-border), fill: c-th-bg,
      text(size: 8pt, weight: "bold", fill: c-muted, upper(label))),
    rect(width: 100%, inset: (x: 10pt, y: 7pt), stroke: (bottom: 0.5pt + c-border),
      if empty { text(fill: c-muted, style: "italic", "—") }
      else { text(size: 9pt, fill: c-text, value) })
  )
}

#grid(
  columns: (auto, 1fr, auto),
  gutter: 12pt,
  align: horizon,
  rect(width: 40pt, height: 40pt, fill: c-red, radius: 3pt,
    align(center + horizon, text(fill: white, weight: "bold", size: 14pt, "APM"))),
  {
    text(weight: "bold", size: 18pt, fill: c-text, elixir_data.school.name)
    linebreak()
    text(size: 9pt, fill: c-muted,
      "Statistically Similar Schools (SSS) Comparison · School " + elixir_data.school.school_code)
  },
  align(right + horizon, {
    text(weight: "bold", size: 10pt, fill: c-text, elixir_data.school_year)
    linebreak()
    text(size: 8pt, fill: c-muted, elixir_data.school.report_date)
  })
)

#v(6pt)
#line(length: 100%, stroke: 1.5pt + c-red)
#v(6pt)

#grid(
  columns: (auto, auto, 1fr),
  gutter: 24pt,
  align: horizon,
  stack(
    text(size: 7.5pt, fill: c-muted, "SCHOOL"),
    v(2pt),
    text(size: 9pt, weight: "semibold", elixir_data.school.name)
  ),
  stack(
    text(size: 7.5pt, fill: c-muted, "SSS PEER GROUP"),
    v(2pt),
    text(size: 9pt, weight: "semibold",
      str(elixir_data.scored_peers) + " scored peers of " + str(elixir_data.total_peers) + " total")
  ),
  []
)

#v(4pt)
#line(length: 100%, stroke: 0.5pt + c-border)
#v(8pt)

#block(fill: c-blue-bg, inset: 10pt, radius: 3pt, width: 100%)[
  #text(size: 8.5pt, fill: c-text)[
    The *SSS Composite* is the simple average of M-STEP and SAT outcomes across
    schools in this Statistically Similar Schools peer group.
  ]
]

#section-title("School Details", subtitle: "MDE entity information")
#let ed = elixir_data.entity_details
#detail-row("ISD Code", ed.isd_code)
#detail-row("ISD Name", ed.isd_official_name)
#detail-row("Entity Type", ed.entity_type_name)
#detail-row("County", ed.county_name)
#detail-row("Chartering Agency Code", ed.chartering_agency_code)
#detail-row("Chartering Agency", ed.chartering_agency_name)
#detail-row("Authorized Grades", ed.authorized_grades)
#detail-row("Actual Grades", ed.actual_grades)

#pagebreak()

#section-title("M-STEP Proficiency",
  subtitle: "School vs SSS composite (% proficient)")
#compare-row("All Subjects Average",
  elixir_data.charter.mstep.avg, elixir_data.composite.mstep.avg, 100)
#compare-row("ELA",
  elixir_data.charter.mstep.ela, elixir_data.composite.mstep.ela, 100)
#compare-row("Mathematics",
  elixir_data.charter.mstep.math, elixir_data.composite.mstep.math, 100)
#compare-row("Science",
  elixir_data.charter.mstep.sci, elixir_data.composite.mstep.sci, 100)
#compare-row("Social Studies",
  elixir_data.charter.mstep.ss, elixir_data.composite.mstep.ss, 100)

#v(2pt)
#table(
  columns: (1.8fr, auto, 1fr, 1fr, 1fr, 1fr, 1fr),
  inset: (x: 8pt, y: 6pt),
  align: (left, right, right, right, right, right, right),
  stroke: none,
  fill: (_, row) => if row == 0 { c-th-bg } else if calc.odd(row) { c-row-alt } else { white },
  table.header(th("Scope"), th("Schools"), th("ELA"), th("Math"), th("Sci"), th("SS"), th("Avg")),
  table.cell(text(weight: "bold", fill: c-school, "School")),
  table.cell(text(fill: c-muted, "—")),
  pct-badge(elixir_data.charter.mstep.ela), pct-badge(elixir_data.charter.mstep.math),
  pct-badge(elixir_data.charter.mstep.sci), pct-badge(elixir_data.charter.mstep.ss),
  pct-badge(elixir_data.charter.mstep.avg),
  table.cell(text(weight: "bold", fill: c-peer, "SSS Composite")),
  [#elixir_data.scored_peers],
  pct-badge(elixir_data.composite.mstep.ela), pct-badge(elixir_data.composite.mstep.math),
  pct-badge(elixir_data.composite.mstep.sci), pct-badge(elixir_data.composite.mstep.ss),
  pct-badge(elixir_data.composite.mstep.avg),
)

#if truthy(elixir_data.has_any_sat) {
  section-title("SAT College Readiness",
    subtitle: "School vs SSS composite (scaled score)")

  compare-row("Math Score",
    elixir_data.charter.sat.math, elixir_data.composite.sat.math, 800, pct: false)
  compare-row("EBRW Score",
    elixir_data.charter.sat.ebrw, elixir_data.composite.sat.ebrw, 800, pct: false)
  compare-row("All Score",
    elixir_data.charter.sat.all, elixir_data.composite.sat.all, 1600, pct: false)

  v(2pt)
  table(
    columns: (2fr, auto, 1fr, 1fr, 1fr),
    inset: (x: 8pt, y: 6pt),
    align: (left, right, right, right, right),
    stroke: none,
    fill: (_, row) => if row == 0 { c-th-bg } else if calc.odd(row) { c-row-alt } else { white },
    table.header(th("Scope"), th("Schools"), th("Math"), th("EBRW"), th("All")),
    table.cell(text(weight: "bold", fill: c-school, "School")),
    table.cell(text(fill: c-muted, "—")),
    score-cell(elixir_data.charter.sat.math), score-cell(elixir_data.charter.sat.ebrw),
    table.cell(text(weight: "bold", score-cell(elixir_data.charter.sat.all))),
    table.cell(text(weight: "bold", fill: c-peer, "SSS Composite")),
    [#elixir_data.scored_peers],
    score-cell(elixir_data.composite.sat.math), score-cell(elixir_data.composite.sat.ebrw),
    table.cell(text(weight: "bold", score-cell(elixir_data.composite.sat.all))),
  )
}

#section-title("SSS Peer Schools — M-STEP",
  subtitle: "Per-school proficiency in the SSS peer group")

#table(
  columns: (2fr, auto, 1fr, 1fr, 1fr, 1fr, 1fr),
  inset: (x: 7pt, y: 5pt),
  align: (left, right, center, center, center, center, center),
  stroke: none,
  fill: (_, row) => if row == 0 { c-th-bg } else if calc.odd(row) { c-row-alt } else { white },
  table.header(th("School"), th("Code"), th("ELA"), th("Math"), th("Sci"), th("SS"), th("Avg")),
  ..elixir_data.peers.map(r => (
    table.cell(align: left, text(size: 8.5pt, r.name)),
    [#r.school_code],
    pct-badge(r.ela), pct-badge(r.math), pct-badge(r.sci), pct-badge(r.ss), pct-badge(r.mstep_avg),
  )).flatten(),
  table.cell(fill: c-green-bg, text(weight: "bold", fill: c-peer, "SSS Composite")),
  table.cell(fill: c-green-bg, align: right, text(weight: "bold", [#elixir_data.scored_peers])),
  table.cell(fill: c-green-bg, pct-badge(elixir_data.composite.mstep.ela)),
  table.cell(fill: c-green-bg, pct-badge(elixir_data.composite.mstep.math)),
  table.cell(fill: c-green-bg, pct-badge(elixir_data.composite.mstep.sci)),
  table.cell(fill: c-green-bg, pct-badge(elixir_data.composite.mstep.ss)),
  table.cell(fill: c-green-bg, pct-badge(elixir_data.composite.mstep.avg)),
)

#if truthy(elixir_data.has_any_sat) {
  section-title("SSS Peer Schools — SAT", subtitle: "Per-school SAT scaled scores")

  table(
    columns: (2.3fr, auto, 1fr, 1fr, 1fr),
    inset: (x: 7pt, y: 5pt),
    align: (left, right, right, right, right),
    stroke: none,
    fill: (_, row) => if row == 0 { c-th-bg } else if calc.odd(row) { c-row-alt } else { white },
    table.header(th("School"), th("Code"), th("Math"), th("EBRW"), th("All")),
    ..elixir_data.peers.map(r => (
      table.cell(align: left, text(size: 8.5pt, r.name)),
      [#r.school_code],
      score-cell(r.sat_math), score-cell(r.sat_ebrw),
      table.cell(text(weight: "bold", score-cell(r.sat_all))),
    )).flatten(),
    table.cell(fill: c-green-bg, text(weight: "bold", fill: c-peer, "SSS Composite")),
    table.cell(fill: c-green-bg, align: right, text(weight: "bold", [#elixir_data.scored_peers])),
    table.cell(fill: c-green-bg, score-cell(elixir_data.composite.sat.math)),
    table.cell(fill: c-green-bg, score-cell(elixir_data.composite.sat.ebrw)),
    table.cell(fill: c-green-bg, text(weight: "bold", score-cell(elixir_data.composite.sat.all))),
  )
}
