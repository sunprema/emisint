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
#let c-pink     = rgb("#db2777")
#let c-pink-bg  = rgb("#fdf2f8")

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
// approximate: true adds a "*" suffix and light gray background to signal a
// Rule 2 range value (e.g. "<=50%" stored as 50).
#let pct-badge(v, school: false, approximate: false) = {
  // JSON round-trip may deliver booleans as strings — normalise to bool
  let approximate = if type(approximate) == str { approximate == "true" } else { approximate }
  // Handle none / nil first
  let v = if v == none { none }
          else if type(v) == str {
            let trimmed = v.trim()
            if trimmed == "nil" or trimmed == "" or trimmed == "N/A" { none }
            else { float(trimmed) }
          } else { v }
  if v == none {
    box(fill: c-row-alt, inset: (x: 7pt, y: 3pt), radius: 3pt,
      text(fill: c-muted, weight: "bold", size: 8.5pt, "—"))
  } else {
    let (bg, fg) = if approximate {
      (luma(220), rgb("#555555"))
    } else if v >= 60 {
      (c-green-bg, c-green)
    } else if v >= 40 {
      (c-amber-bg, c-amber)
    } else {
      (c-red-bg, c-red)
    }
    let label = str(calc.round(v, digits: 1)) + "%" + if approximate { "*" } else { "" }
    box(fill: bg, inset: (x: 7pt, y: 3pt), radius: 3pt,
      text(fill: fg, weight: "bold", size: 8.5pt, label))
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

// SAT score bar: school (blue) / LEA (amber) / State (green) scaled to max-score
#let sat-score-bar(subject, school, compare, state, max-score) = {
  let s_pct  = if school  != none { calc.min(school  / max-score, 1.0) } else { 0.0 }
  let c_pct  = if compare != none { calc.min(compare / max-score, 1.0) } else { 0.0 }
  let st_pct = if state   != none { calc.min(state   / max-score, 1.0) } else { 0.0 }

  block(width: 100%, spacing: 0pt, {
    // Header row: label + score badges
    grid(
      columns: (1fr, auto, auto, auto),
      gutter: 8pt,
      align: (left + horizon, right + horizon, right + horizon, right + horizon),
      text(size: 9pt, weight: "semibold", subject),
      if state != none {
        box(fill: c-green-bg, inset: (x: 6pt, y: 2pt), radius: 3pt,
          text(fill: c-green, weight: "bold", size: 8pt, str(calc.round(state, digits: 0))))
      },
      if compare != none {
        box(fill: c-amber-bg, inset: (x: 6pt, y: 2pt), radius: 3pt,
          text(fill: c-amber, weight: "bold", size: 8pt, str(calc.round(compare, digits: 0))))
      },
      if school != none {
        box(fill: c-blue-bg, inset: (x: 6pt, y: 2pt), radius: 3pt,
          text(fill: c-blue, weight: "bold", size: 8pt, str(calc.round(school, digits: 0))))
      } else {
        box(fill: c-row-alt, inset: (x: 6pt, y: 2pt), radius: 3pt,
          text(fill: c-muted, weight: "bold", size: 8pt, "—"))
      }
    )
    v(5pt)
    // School bar
    grid(
      columns: (s_pct * 100% + 0.01%, 1fr),
      rows: 7pt,
      rect(width: 100%, height: 100%, fill: c-school,
        radius: (left: 2pt, right: if s_pct >= 0.99 { 2pt } else { 0pt })),
      rect(width: 100%, height: 100%, fill: c-border, radius: (right: 2pt))
    )
    if compare != none {
      v(2pt)
      grid(
        columns: (c_pct * 100% + 0.01%, 1fr),
        rows: 7pt,
        rect(width: 100%, height: 100%, fill: c-lea,
          radius: (left: 2pt, right: if c_pct >= 0.99 { 2pt } else { 0pt })),
        rect(width: 100%, height: 100%, fill: c-border, radius: (right: 2pt))
      )
    }
    if state != none {
      v(2pt)
      grid(
        columns: (st_pct * 100% + 0.01%, 1fr),
        rows: 7pt,
        rect(width: 100%, height: 100%, fill: c-green,
          radius: (left: 2pt, right: if st_pct >= 0.99 { 2pt } else { 0pt })),
        rect(width: 100%, height: 100%, fill: c-border, radius: (right: 2pt))
      )
    }
    v(4pt)
    // Scale labels
    grid(
      columns: (1fr, 1fr, 1fr, 1fr, 1fr),
      align: (left, center, center, center, right),
      text(size: 7pt, fill: c-muted, "0"),
      text(size: 7pt, fill: c-muted, str(max-score / 4)),
      text(size: 7pt, fill: c-muted, str(max-score / 2)),
      text(size: 7pt, fill: c-muted, str(max-score * 3 / 4)),
      text(size: 7pt, fill: c-muted, str(max-score))
    )
  })
}

// Integer formatter (nil → em dash)
#let fmt-int(v) = if v == none { "—" } else { str(v) }

// Percentage sub-label for stat boxes
#let fmt-pct-sub(v) = if v == none { "" } else { str(calc.round(v, digits: 1)) + "% of enrollment" }

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

// ── Section 0: School Details ─────────────────────────────────────────────────
#section-title("School Details", subtitle: "MDE entity information")

#let detail-row(label, value) = {
  grid(
    columns: (120pt, 1fr),
    gutter: 0pt,
    rect(
      width: 100%, inset: (x: 10pt, y: 7pt),
      stroke: (bottom: 0.5pt + c-border, right: 0.5pt + c-border),
      fill: c-th-bg,
      text(size: 8pt, weight: "bold", fill: c-muted, upper(label))
    ),
    rect(
      width: 100%, inset: (x: 10pt, y: 7pt),
      stroke: (bottom: 0.5pt + c-border),
      text(size: 9pt, fill: c-text, if value == none or value == "" { text(fill: c-muted, style: "italic", "—") } else { value })
    )
  )
}

#let ed = elixir_data.entity_details

#detail-row("ISD Code", ed.isd_code)
#detail-row("ISD Name", ed.isd_official_name)
#detail-row("Chartering Agency Code", ed.entity_chartering_agency_code)
#detail-row("Chartering Agency", ed.entity_chartering_agency_name)
#detail-row("Authorized Grades", ed.entity_authorized_grades)
#detail-row("Actual Grades", ed.entity_actual_grades)

// ── Section 1 (Page 1): Student Enrollment ────────────────────────────────────
#section-title("Student Enrollment",
  subtitle: "Building-level student body composition · " + elixir_data.school_year)

#if elixir_data.enrollment.total == none [
  #rect(
    width: 100%, inset: 14pt, stroke: 0.5pt + c-border, radius: 2pt,
    text(fill: c-muted, style: "italic", "No enrollment data available for this school year.")
  )
] else [
  #grid(
    columns: (1fr, 1fr, 1fr),
    gutter: 10pt,
    stat-box("Total Enrolled",
      fmt-int(elixir_data.enrollment.total),
      sub: "all students"),
    stat-box("Male",
      fmt-int(elixir_data.enrollment.male),
      sub: fmt-pct-sub(elixir_data.enrollment.male_pct)),
    stat-box("Female",
      fmt-int(elixir_data.enrollment.female),
      sub: fmt-pct-sub(elixir_data.enrollment.female_pct))
  )
  #if elixir_data.enrollment.male_pct != none [
    #v(14pt)
    // Legend
    #grid(
      columns: (auto, 1fr, auto),
      {
        box(width: 10pt, height: 8pt, fill: c-school, radius: 1pt)
        h(5pt)
        text(size: 8pt, fill: c-muted, "Male")
      },
      [],
      {
        box(width: 10pt, height: 8pt, fill: c-pink, radius: 1pt)
        h(5pt)
        text(size: 8pt, fill: c-muted, "Female")
      }
    )
    #v(4pt)
    // Proportional gender bar
    #let mp = calc.max(calc.min(elixir_data.enrollment.male_pct / 100, 0.99), 0.01)
    #let fp = 1.0 - mp
    #grid(
      columns: (mp * 100%, fp * 100%),
      rows: 26pt,
      rect(
        width: 100%, height: 100%, fill: c-school,
        radius: (left: 4pt, right: 0pt),
        align(center + horizon,
          text(fill: white, weight: "bold", size: 9pt,
            str(calc.round(elixir_data.enrollment.male_pct, digits: 1)) + "%")
        )
      ),
      rect(
        width: 100%, height: 100%, fill: c-pink,
        radius: (right: 4pt, left: 0pt),
        align(center + horizon,
          text(fill: white, weight: "bold", size: 9pt,
            str(calc.round(elixir_data.enrollment.female_pct, digits: 1)) + "%")
        )
      )
    )
  ]
]

#pagebreak()

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

#pagebreak()

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
      align(center, pct-badge(row.school_ela, approximate: row.school_ela_approximate)),
      align(center, pct-badge(row.lea_ela)),
      align(center, pct-badge(row.state_ela)),
      align(center, pct-badge(row.school_math, approximate: row.school_math_approximate)),
      align(center, pct-badge(row.lea_math)),
      align(center, pct-badge(row.state_math))
    )}
  )
]

#pagebreak()

// ── Section 4: SAT College Readiness ──────────────────────────────────────────
#section-title("SAT College Readiness",
  subtitle: "Average scale scores by subgroup · All Students & Economically Disadvantaged · " + elixir_data.school_year)

#let fmt-score(v, fg) = {
  if v == none {
    text(fill: c-muted, size: 8.5pt, "—")
  } else {
    text(fill: fg, weight: "bold", size: 8.5pt, str(calc.round(v, digits: 1)))
  }
}

#if elixir_data.sat_results.len() == 0 [
  #rect(
    width: 100%, inset: 14pt, stroke: 0.5pt + c-border, radius: 2pt,
    text(fill: c-muted, style: "italic", "No SAT college-readiness data available for this school year.")
  )
] else [
  #table(
    columns: (1.8fr, 0.7fr, 1fr, 1fr, 1fr),
    stroke: (x, y) => if y == 0 { none } else { (bottom: 0.5pt + c-border) },
    inset: (x: 7pt, y: 8pt),
    fill: (x, y) => if y == 0 { c-th-bg } else if calc.odd(y) { white } else { c-row-alt },
    th("Subgroup"),
    th("Assessed"),
    th("Math Score"),
    th("EBRW Score"),
    th("All Score"),
    ..for row in elixir_data.sat_results {(
      text(size: 9pt, weight: "semibold", row.subgroup),
      align(center, text(size: 8.5pt, fill: c-muted, if row.num_assessed == none { "—" } else { str(row.num_assessed) })),
      align(center, fmt-score(row.math_score_average, c-school)),
      align(center, fmt-score(row.ebrw_score_average, c-green)),
      align(center, fmt-score(row.all_subject_score_average, c-lea))
    )}
  )
  #v(6pt)
  #text(size: 8pt, fill: c-muted)[
    Average SAT scale scores: Math 200–800 · EBRW 200–800 · All 400–1600.
    #box(fill: c-blue-bg, inset:(x:5pt,y:2pt), radius:3pt,
      stroke: 0.5pt + c-school.lighten(40%),
      text(fill:c-school, size:7.5pt, weight:"bold", "Math Score"))
    #h(5pt)
    #box(fill: c-green-bg, inset:(x:5pt,y:2pt), radius:3pt,
      stroke: 0.5pt + c-green.lighten(40%),
      text(fill:c-green, size:7.5pt, weight:"bold", "EBRW Score"))
    #h(5pt)
    #box(fill: c-amber-bg, inset:(x:5pt,y:2pt), radius:3pt,
      stroke: 0.5pt + c-amber.lighten(40%),
      text(fill:c-amber, size:7.5pt, weight:"bold", "All Score"))
  ]
]


// ── Section 5: SAT College Readiness by Subject (Score Bars) ─────────────────
#if elixir_data.sat_score_bars.len() > 0 [
  #section-title("SAT College Readiness by Subject",
    subtitle: "Average scale scores · All Students · " + elixir_data.school_year)

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

  #rect(width: 100%, inset: 16pt, stroke: 0.75pt + c-border, radius: 2pt, {
    for (i, bar) in elixir_data.sat_score_bars.enumerate() {
      if i > 0 {
        v(14pt)
        line(length: 100%, stroke: 0.5pt + c-border)
        v(10pt)
      }
      sat-score-bar(bar.subject, bar.school, bar.lea, bar.state, bar.max_val)
    }
  })

  #v(6pt)
  #text(size: 8pt, fill: c-muted)[
    Scores are average SAT scale scores (Math: 200–800, EBRW: 200–800, All: 400–1600).
    #box(fill: c-blue-bg, inset: (x: 5pt, y: 2pt), radius: 3pt,
      stroke: 0.5pt + c-blue.lighten(40%),
      text(fill: c-blue, size: 7.5pt, weight: "bold", "School"))
    #h(5pt)
    #box(fill: c-amber-bg, inset: (x: 5pt, y: 2pt), radius: 3pt,
      stroke: 0.5pt + c-amber.lighten(40%),
      text(fill: c-amber, size: 7.5pt, weight: "bold", "Geographic LEA"))
    #h(5pt)
    #box(fill: c-green-bg, inset: (x: 5pt, y: 2pt), radius: 3pt,
      stroke: 0.5pt + c-green.lighten(40%),
      text(fill: c-green, size: 7.5pt, weight: "bold", "State Avg"))
  ]
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
