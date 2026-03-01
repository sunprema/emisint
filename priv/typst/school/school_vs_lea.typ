// Emisint — School vs Geographic LEA District Comparison Report
// Design: matches comprehensive.typ palette and layout

// ── Colour palette ────────────────────────────────────────────────────────────
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
#let c-lea      = rgb("#b45309")

// ── Page layout ───────────────────────────────────────────────────────────────
#set page(
  paper: "us-letter",
  margin: (top: 0.85in, bottom: 0.85in, left: 0.85in, right: 0.85in),
  header: context {
    if counter(page).get().first() > 1 [
      #set text(size: 8pt, fill: c-muted, font: "Helvetica Neue")
      #grid(
        columns: (1fr, auto),
        align: (horizon + left, horizon + right),
        gutter: 0pt,
        [#elixir_data.school.name #h(6pt) #text(fill: c-border, "│") #h(6pt) School vs Geographic LEA Comparison],
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

// ── Helpers ───────────────────────────────────────────────────────────────────

#let capitalize(s) = {
  if s.len() == 0 { s }
  else { upper(s.first()) + s.slice(1) }
}

// Section header with left red bar
#let section-title(title, subtitle: "") = {
  v(20pt)
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

// KPI stat box
#let stat-box(label, value, sub: "") = rect(
  width: 100%,
  inset: (x: 14pt, y: 12pt),
  stroke: 0.75pt + c-border,
  radius: 2pt,
  {
    text(size: 8pt, fill: c-muted, upper(label))
    v(4pt)
    text(size: 22pt, weight: "bold", fill: c-blue, value)
    if sub != "" {
      linebreak()
      text(size: 7.5pt, fill: c-muted, sub)
    }
  }
)

// Table header cell
#let th(t) = table.cell(
  fill: c-th-bg,
  text(weight: "bold", size: 8pt, fill: c-muted, upper(t))
)

// Proficiency % badge — colour-coded by threshold (value is 0–100)
#let pct-badge(v, school: false) = {
  if v == none {
    box(fill: c-row-alt, inset: (x: 7pt, y: 3pt), radius: 3pt,
      text(fill: c-muted, weight: "bold", size: 8.5pt, "—"))
  } else {
    let (bg, fg) = if v >= 60 {
      (c-green-bg, c-green)
    } else if v >= 40 {
      (c-amber-bg, c-amber)
    } else {
      (c-red-bg, c-red)
    }
    box(fill: bg, inset: (x: 7pt, y: 3pt), radius: 3pt,
      text(fill: fg, weight: "bold", size: 8.5pt, str(calc.round(v, digits: 1)) + "%"))
  }
}

// Delta badge: positive = school leads (green), negative = school trails (red)
#let delta-badge(v) = {
  if v == none {
    box(fill: c-row-alt, inset: (x: 6pt, y: 3pt), radius: 3pt,
      text(fill: c-muted, size: 8pt, "—"))
  } else {
    let (bg, fg) = if v >= 0 { (c-green-bg, c-green) } else { (c-red-bg, c-red) }
    let label = if v >= 0 {
      "+" + str(calc.round(v, digits: 1)) + " pts"
    } else {
      str(calc.round(v, digits: 1)) + " pts"
    }
    box(fill: bg, inset: (x: 6pt, y: 3pt), radius: 3pt,
      text(fill: fg, weight: "bold", size: 8pt, label))
  }
}

// Tri progress bar: school (blue, top) vs LEA (amber, middle) vs State (green, bottom)
#let tri-bar(school_v, lea_v, state_v) = {
  let s_pct  = if school_v != none { calc.min(school_v / 100, 1.0) } else { 0.0 }
  let l_pct  = if lea_v    != none { calc.min(lea_v    / 100, 1.0) } else { 0.0 }
  let st_pct = if state_v  != none { calc.min(state_v  / 100, 1.0) } else { 0.0 }
  block(width: 100%, {
    // School bar
    grid(
      columns: (s_pct * 100% + 0.01%, 1fr),
      rows: 7pt,
      rect(width: 100%, height: 100%, fill: c-school,
        radius: (left: 2pt, right: if s_pct >= 0.99 { 2pt } else { 0pt })),
      rect(width: 100%, height: 100%, fill: c-border,
        radius: (right: 2pt))
    )
    v(2pt)
    // LEA bar
    grid(
      columns: (l_pct * 100% + 0.01%, 1fr),
      rows: 7pt,
      rect(width: 100%, height: 100%, fill: c-lea,
        radius: (left: 2pt, right: if l_pct >= 0.99 { 2pt } else { 0pt })),
      rect(width: 100%, height: 100%, fill: c-border,
        radius: (right: 2pt))
    )
    v(2pt)
    // State bar
    grid(
      columns: (st_pct * 100% + 0.01%, 1fr),
      rows: 7pt,
      rect(width: 100%, height: 100%, fill: c-green,
        radius: (left: 2pt, right: if st_pct >= 0.99 { 2pt } else { 0pt })),
      rect(width: 100%, height: 100%, fill: c-border,
        radius: (right: 2pt))
    )
  })
}

// ── Page 1: Cover Header ──────────────────────────────────────────────────────

#grid(
  columns: (auto, 1fr, auto),
  gutter: 12pt,
  align: horizon,
  rect(
    width: 40pt, height: 40pt,
    fill: c-red,
    radius: 3pt,
    align(center + horizon,
      text(fill: white, weight: "bold", size: 14pt, "APM")
    )
  ),
  {
    text(weight: "bold", size: 18pt, fill: c-text, elixir_data.school.name)
    linebreak()
    text(size: 9pt, fill: c-muted,
      "School vs Geographic LEA District Comparison" +
      if elixir_data.school.building_code != "" {
        " · MDE " + elixir_data.school.building_code
      } else { "" }
    )
  },
  align(right + horizon, {
    text(weight: "bold", size: 10pt, fill: c-text, elixir_data.school_year)
    linebreak()
    text(size: 8pt, fill: c-muted, elixir_data.school.report_date)
  })
)

#v(6pt)
#line(length: 100%, stroke: 1.5pt + c-red)
#v(4pt)

// School + LEA identity strip
#grid(
  columns: (auto, auto, 1fr),
  gutter: 20pt,
  align: horizon,
  stack(
    text(size: 7.5pt, fill: c-muted, "SCHOOL"),
    v(2pt),
    text(size: 9pt, weight: "semibold", elixir_data.school.name)
  ),
  if elixir_data.lea.district_name != "" {
    stack(
      text(size: 7.5pt, fill: c-muted, "GEOGRAPHIC LEA DISTRICT"),
      v(2pt),
      text(size: 9pt, weight: "semibold", elixir_data.lea.district_name)
    )
  } else if elixir_data.lea.district_code != "" {
    stack(
      text(size: 7.5pt, fill: c-muted, "GEOGRAPHIC LEA DISTRICT CODE"),
      v(2pt),
      text(size: 9pt, weight: "semibold", elixir_data.lea.district_code)
    )
  } else {
    stack(
      text(size: 7.5pt, fill: c-muted, "GEOGRAPHIC LEA DISTRICT"),
      v(2pt),
      text(size: 9pt, fill: c-muted, style: "italic", "Not mapped in MDE Entity Master")
    )
  },
  []
)

#v(2pt)
#line(length: 100%, stroke: 0.5pt + c-border)

// ── KPI Summary ───────────────────────────────────────────────────────────────
#section-title("Comparison Summary", subtitle: "M-STEP proficiency — school vs geographic LEA district")

#grid(
  columns: (1fr, 1fr, 1fr, 1fr),
  gutter: 10pt,
  stat-box("Subjects Above LEA",
    str(elixir_data.above_lea),
    sub: "school outperforms district"),
  stat-box("Subjects Below LEA",
    str(elixir_data.below_lea),
    sub: "school trails district"),
  stat-box("Subjects Above State",
    str(elixir_data.above_state),
    sub: "school vs state average"),
  stat-box("Grades Compared",
    str(elixir_data.grades_compared),
    sub: "grade levels with data"),
)

// ── Section 1: Subject Proficiency ────────────────────────────────────────────
#section-title("M-STEP Proficiency by Subject",
  subtitle: "All Students · " + elixir_data.school_year)

// Legend
#grid(
  columns: (auto, auto, auto, 1fr),
  gutter: 14pt,
  align: horizon,
  {
    box(width: 10pt, height: 7pt, fill: c-school, radius: 1pt)
    h(5pt)
    text(size: 8pt, fill: c-muted, elixir_data.school.name)
  },
  {
    box(width: 10pt, height: 7pt, fill: c-lea, radius: 1pt)
    h(5pt)
    text(size: 8pt, fill: c-muted,
      if elixir_data.lea.district_name != "" { elixir_data.lea.district_name }
      else { "Geographic LEA District" }
    )
  },
  {
    box(width: 10pt, height: 7pt, fill: c-green, radius: 1pt)
    h(5pt)
    text(size: 8pt, fill: c-muted, "Michigan State Avg")
  },
  []
)
#v(8pt)

#table(
  columns: (1.4fr, 0.75fr, 2fr, 0.75fr, 0.75fr, 0.85fr),
  stroke: (x, y) => if y == 0 { none } else { (bottom: 0.5pt + c-border) },
  inset: (x: 8pt, y: 9pt),
  fill: (x, y) => if y == 0 { c-th-bg } else if calc.odd(y) { white } else { c-row-alt },
  th("Subject"),
  th("School %"),
  th(""),
  th("LEA %"),
  th("State %"),
  th("Δ vs LEA"),
  table.hline(stroke: 1pt + c-border),
  table.cell(fill: c-th-bg, text(size: 9pt, weight: "bold", fill: c-text, "All Subjects Avg")),
  table.cell(fill: c-th-bg, align(center, pct-badge(elixir_data.all_subjects_avg.school_pct))),
  table.cell(fill: c-th-bg, tri-bar(elixir_data.all_subjects_avg.school_pct, elixir_data.all_subjects_avg.lea_pct, elixir_data.all_subjects_avg.state_pct)),
  table.cell(fill: c-th-bg, align(center, pct-badge(elixir_data.all_subjects_avg.lea_pct))),
  table.cell(fill: c-th-bg, align(center, pct-badge(elixir_data.all_subjects_avg.state_pct))),
  table.cell(fill: c-th-bg, align(center, delta-badge(elixir_data.all_subjects_avg.delta))),
  ..for s in elixir_data.subjects {(
    text(size: 9pt, weight: "semibold", s.subject),
    align(center, pct-badge(s.school_pct)),
    tri-bar(s.school_pct, s.lea_pct, s.state_pct),
    align(center, pct-badge(s.lea_pct)),
    align(center, pct-badge(s.state_pct)),
    align(center, delta-badge(s.delta))
  )},
  
)

#v(6pt)
#text(size: 8pt, fill: c-muted)[
  Proficiency thresholds:
  #box(fill: c-green-bg, inset:(x:5pt,y:2pt), radius:3pt,
    stroke: 0.5pt + c-green.lighten(40%),
    text(fill:c-green, size:7.5pt, weight:"bold", "≥ 60% Strong"))
  #h(5pt)
  #box(fill: c-amber-bg, inset:(x:5pt,y:2pt), radius:3pt,
    stroke: 0.5pt + c-amber.lighten(40%),
    text(fill:c-amber, size:7.5pt, weight:"bold", "40–59% Typical"))
  #h(5pt)
  #box(fill: c-red-bg, inset:(x:5pt,y:2pt), radius:3pt,
    stroke: 0.5pt + c-red.lighten(40%),
    text(fill:c-red, size:7.5pt, weight:"bold", "< 40% Below"))
  #h(10pt)
  Delta = School % − LEA %
]

// ── Section 2: Grade-Level Breakdown ─────────────────────────────────────────
#section-title("Grade-Level Breakdown",
  subtitle: "ELA and Mathematics proficiency by grade — school vs geographic LEA district")

#if elixir_data.grade_breakdown.len() == 0 [
  #rect(
    width: 100%, inset: 14pt, stroke: 0.5pt + c-border, radius: 2pt,
    text(fill: c-muted, style: "italic", "No grade-level data available.")
  )
] else [
  #table(
    columns: (auto, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr),
    stroke: (x, y) => if y == 0 { none } else { (bottom: 0.5pt + c-border) },
    inset: (x: 7pt, y: 8pt),
    fill: (x, y) => if y == 0 { c-th-bg } else if calc.odd(y) { white } else { c-row-alt },
    th("Grade"),
    th("Sch ELA"),
    th("LEA ELA"),
    th("St ELA"),
    th("Sch Math"),
    th("LEA Math"),
    th("St Math"),
    ..for row in elixir_data.grade_breakdown {(
      text(size: 9pt, weight: "semibold", row.grade),
      align(center, pct-badge(row.school_ela)),
      align(center, pct-badge(row.lea_ela)),
      align(center, pct-badge(row.state_ela)),
      align(center, pct-badge(row.school_math)),
      align(center, pct-badge(row.lea_math)),
      align(center, pct-badge(row.state_math))
    )}
  )
]

// ── Signature block ────────────────────────────────────────────────────────────
#v(1fr)
#line(length: 100%, stroke: 0.5pt + c-border)
#v(6pt)
#grid(
  columns: (1fr, 1fr),
  gutter: 40pt,
  {
    line(length: 80%, stroke: 0.75pt + c-border)
    v(3pt)
    text(size: 8pt, fill: c-muted, "EMO Academic Officer Signature")
  },
  {
    line(length: 80%, stroke: 0.75pt + c-border)
    v(3pt)
    text(size: 8pt, fill: c-muted, "Date of Review")
  }
)
