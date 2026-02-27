// Emisint — Comprehensive School Report
// Design: clean corporate style with red accent

// ── Colour palette ───────────────────────────────────────────────────────────
#let c-red      = rgb("#b91c1c")
#let c-red-bg   = rgb("#fef2f2")
#let c-blue     = rgb("#1d4ed8")
#let c-green    = rgb("#15803d")
#let c-green-bg = rgb("#f0fdf4")
#let c-amber    = rgb("#b45309")
#let c-amber-bg = rgb("#fffbeb")
#let c-text     = rgb("#1e293b")
#let c-muted    = rgb("#64748b")
#let c-border   = rgb("#e2e8f0")
#let c-row-alt  = rgb("#f8fafc")
#let c-th-bg    = rgb("#f1f5f9")

// ── Page layout ──────────────────────────────────────────────────────────────
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
        [#elixir_data.school.name #h(6pt) #text(fill: c-border, "│") #h(6pt) Academic Performance Report],
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

// ── Helpers ──────────────────────────────────────────────────────────────────

#let capitalize(s) = {
  if s.len() == 0 { s }
  else { upper(s.first()) + s.slice(1) }
}

// Section header with left red bar — matches screenshot style
#let section-title(title, subtitle: "") = {
  v(20pt)
  grid(
    columns: (4pt, 1fr),
    gutter: 10pt,
    // Red left bar
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

// Stat box — large number with label, matches screenshot KPI cards
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

// Status badge (pill)
#let status-badge(s) = {
  let (bg, fg, label) = if s == "exceeds" {
    (c-green-bg, c-green, "Exceeds")
  } else if s == "meets" {
    (rgb("#eff6ff"), c-blue, "Meets")
  } else if s == "approaching" {
    (c-amber-bg, c-amber, "Approaching")
  } else if s == "below" {
    (c-red-bg, c-red, "Below")
  } else if s == "insufficient_data" {
    (rgb("#f8fafc"), c-muted, "Insuff. Data")
  } else {
    (rgb("#f8fafc"), c-muted, "No Data")
  }
  box(
    fill: bg,
    inset: (x: 7pt, y: 3pt),
    radius: 10pt,
    stroke: 0.5pt + bg.darken(15%),
    text(fill: fg, weight: "bold", size: 7.5pt, label)
  )
}

// Severity badge
#let severity-badge(s) = {
  let (bg, fg) = if s == "high" {
    (c-red-bg, c-red)
  } else if s == "medium" {
    (c-amber-bg, c-amber)
  } else {
    (rgb("#f0f9ff"), rgb("#0369a1"))
  }
  box(
    fill: bg,
    inset: (x: 6pt, y: 3pt),
    radius: 10pt,
    text(fill: fg, weight: "bold", size: 7.5pt, upper(s))
  )
}

// Proficiency % badge
#let pct-badge(rate) = {
  let (bg, fg) = if rate >= 0.6 {
    (c-green-bg, c-green)
  } else if rate >= 0.4 {
    (c-amber-bg, c-amber)
  } else {
    (c-red-bg, c-red)
  }
  let pct = str(calc.round(rate * 100, digits: 1)) + "%"
  box(fill: bg, inset: (x: 7pt, y: 3pt), radius: 3pt,
    text(fill: fg, weight: "bold", size: 8.5pt, pct))
}

// SGP colored number
#let sgp-text(val) = {
  let fg = if val >= 50 { c-green } else if val >= 40 { c-amber } else { c-red }
  text(fill: fg, weight: "bold", str(calc.round(val, digits: 1)))
}

// ── Page 1: Cover Header ──────────────────────────────────────────────────────
#grid(
  columns: (auto, 1fr, auto),
  gutter: 12pt,
  align: horizon,
  // Red icon square — mimics screenshot logo treatment
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
      if elixir_data.school.city != "" { elixir_data.school.city + " · " } else { "" } +
      if elixir_data.school.mde_building_code != "" { "MDE " + elixir_data.school.mde_building_code + " · " } else { "" } +
      "Academic Performance Report"
    )
  },
  align(right + horizon, {
    text(weight: "bold", size: 10pt, fill: c-text, elixir_data.academic_year)
    linebreak()
    text(size: 8pt, fill: c-muted, elixir_data.school.report_date)
  })
)

#v(6pt)
#line(length: 100%, stroke: 1.5pt + c-red)
#v(4pt)

// Contract summary line
#if elixir_data.contract.authorizer != "" or elixir_data.contract.status != "" [
  #grid(
    columns: (auto, auto, auto, 1fr),
    gutter: 20pt,
    align: horizon,
    if elixir_data.contract.authorizer != "" {
      stack(
        text(size: 7.5pt, fill: c-muted, "AUTHORIZER"),
        v(2pt),
        text(size: 9pt, weight: "semibold", elixir_data.contract.authorizer)
      )
    },
    if elixir_data.contract.status != "" {
      stack(
        text(size: 7.5pt, fill: c-muted, "CONTRACT STATUS"),
        v(2pt),
        text(size: 9pt, weight: "semibold", upper(elixir_data.contract.status))
      )
    },
    if elixir_data.contract.start_date != "" {
      stack(
        text(size: 7.5pt, fill: c-muted, "CONTRACT PERIOD"),
        v(2pt),
        text(size: 9pt, weight: "semibold",
          elixir_data.contract.start_date + " – " + elixir_data.contract.end_date)
      )
    },
    []
  )
  #v(2pt)
  #line(length: 100%, stroke: 0.5pt + c-border)
]

// ── KPI Summary ───────────────────────────────────────────────────────────────
#section-title("General Summary", subtitle: "Key performance indicators for this school")

#let total_students = elixir_data.proficiency.fold(0, (acc, r) => acc + r.student_count)
#let goals_count    = elixir_data.goals.len()
#let meets_count    = elixir_data.goals.filter(g => g.status == "meets" or g.status == "exceeds").len()
#let triggers_count = elixir_data.active_triggers.len()

#grid(
  columns: (1fr, 1fr, 1fr, 1fr),
  gutter: 10pt,
  stat-box("Students Assessed", str(total_students),
    sub: "proficiency windows"),
  stat-box("Goals on Track",
    if goals_count > 0 { str(meets_count) + "/" + str(goals_count) } else { "—" },
    sub: "meets or exceeds"),
  stat-box("Active Triggers", str(triggers_count),
    sub: if triggers_count == 0 { "no interventions" } else { "require attention" }),
  stat-box("Data Windows", str(elixir_data.proficiency.len() + elixir_data.growth.len()),
    sub: "assessment records"),
)

// ── Section 1: Proficiency ───────────────────────────────────────────────────
#section-title("State Assessment Proficiency",
  subtitle: "School-wide proficiency rates by subject and testing window")

#if elixir_data.proficiency.len() == 0 [
  #rect(
    width: 100%, inset: 14pt, stroke: 0.5pt + c-border, radius: 2pt,
    text(fill: c-muted, style: "italic", "No proficiency data available for this school.")
  )
] else [
  #let subjects = elixir_data.proficiency.map(s => s.subject).dedup()

  #for subject in subjects [
    #v(10pt)
    #text(weight: "bold", size: 9.5pt, fill: c-text, capitalize(subject))
    #v(5pt)
    #table(
      columns: (2fr, 1.2fr, 2.8fr, 1fr),
      stroke: (x, y) => if y == 0 { none } else { (bottom: 0.5pt + c-border) },
      inset: (x: 10pt, y: 8pt),
      fill: (x, y) => if y == 0 { c-th-bg } else if calc.odd(y) { white } else { c-row-alt },
      th("Testing Window"), th("Proficiency %"), th("Rate"), th("Students"),
      ..for row in elixir_data.proficiency.filter(s => s.subject == subject) {(
        text(size: 9pt, capitalize(row.testing_window)),
        pct-badge(row.proficiency_rate),
        // Progress bar
        block(height: 10pt, width: 100%, {
          let pct = calc.min(row.proficiency_rate, 1.0)
          let bar_color = if pct >= 0.6 { c-green } else if pct >= 0.4 { c-amber } else { c-red }
          grid(
            columns: (pct * 100% + 0.01%, 1fr),
            rows: 10pt,
            rect(width: 100%, height: 100%, fill: bar_color,
              radius: (left: 2pt, right: if pct >= 0.99 { 2pt } else { 0pt })),
            rect(width: 100%, height: 100%, fill: c-border,
              radius: (right: 2pt))
          )
        }),
        text(size: 9pt, fill: c-muted, str(row.student_count))
      )}
    )
  ]
  #v(6pt)
  #text(size: 8pt, fill: c-muted)[
    Color key: #box(fill: c-green-bg, inset:(x:5pt,y:2pt), radius:3pt,
      stroke: 0.5pt + c-green.lighten(40%),
      text(fill:c-green,size:7.5pt,weight:"bold","≥ 60% Strong"))
    #h(5pt)
    #box(fill: c-amber-bg, inset:(x:5pt,y:2pt), radius:3pt,
      stroke: 0.5pt + c-amber.lighten(40%),
      text(fill:c-amber,size:7.5pt,weight:"bold","40–59% Typical"))
    #h(5pt)
    #box(fill: c-red-bg, inset:(x:5pt,y:2pt), radius:3pt,
      stroke: 0.5pt + c-red.lighten(40%),
      text(fill:c-red,size:7.5pt,weight:"bold","< 40% Below"))
  ]
]

// ── Section 2: Growth (SGP) ───────────────────────────────────────────────────
#section-title("Student Growth Percentiles (SGP)",
  subtitle: "By-grade SGP data — median ≥ 50 indicates strong growth")

#if elixir_data.growth.len() == 0 [
  #rect(
    width: 100%, inset: 14pt, stroke: 0.5pt + c-border, radius: 2pt,
    text(fill: c-muted, style: "italic", "No SGP data available for this school.")
  )
] else [
  #table(
    columns: (auto, 1.3fr, 1.6fr, 1fr, 1fr, 0.8fr),
    stroke: (x, y) => if y == 0 { none } else { (bottom: 0.5pt + c-border) },
    inset: (x: 10pt, y: 8pt),
    fill: (x, y) => if y == 0 { c-th-bg } else if calc.odd(y) { white } else { c-row-alt },
    th("Grade"), th("Subject"), th("Window"), th("Median SGP"), th("Avg SGP"), th("Students"),
    ..for row in elixir_data.growth {(
      text(size: 9pt, weight: "semibold", row.grade_level),
      text(size: 9pt, capitalize(row.subject)),
      text(size: 9pt, fill: c-muted, capitalize(row.testing_window)),
      sgp-text(row.median_sgp),
      text(size: 9pt, fill: c-muted, str(calc.round(row.average_sgp, digits: 1))),
      text(size: 9pt, fill: c-muted, str(row.student_count))
    )}
  )
  #v(6pt)
  #text(size: 8pt, fill: c-muted)[
    SGP key: #box(fill: c-green-bg, inset:(x:5pt,y:2pt), radius:3pt,
      stroke: 0.5pt + c-green.lighten(40%),
      text(fill:c-green,size:7.5pt,weight:"bold","≥ 50 Strong"))
    #h(5pt)
    #box(fill: c-amber-bg, inset:(x:5pt,y:2pt), radius:3pt,
      stroke: 0.5pt + c-amber.lighten(40%),
      text(fill:c-amber,size:7.5pt,weight:"bold","40–49 Typical"))
    #h(5pt)
    #box(fill: c-red-bg, inset:(x:5pt,y:2pt), radius:3pt,
      stroke: 0.5pt + c-red.lighten(40%),
      text(fill:c-red,size:7.5pt,weight:"bold","< 40 Below"))
  ]
]

// ── Section 3: Schedule 7-1 Compliance ───────────────────────────────────────
#section-title("Schedule 7-1 Contractual Compliance",
  subtitle: "Shows whether live performance meets each charter contract goal")

#if elixir_data.goals.len() == 0 [
  #rect(
    width: 100%, inset: 14pt, stroke: 0.5pt + c-border, radius: 2pt,
    text(fill: c-muted, style: "italic", "No Schedule 7-1 goals configured for this school.")
  )
] else [
  #table(
    columns: (2.5fr, 1.2fr, 1fr, 0.85fr, 0.85fr, 1.1fr),
    stroke: (x, y) => if y == 0 { none } else { (bottom: 0.5pt + c-border) },
    inset: (x: 10pt, y: 8pt),
    fill: (x, y) => if y == 0 { c-th-bg } else if calc.odd(y) { white } else { c-row-alt },
    th("Goal"), th("Type"), th("Subject"), th("Target"), th("Actual"), th("Status"),
    ..for g in elixir_data.goals {(
      text(size: 9pt, weight: "medium", g.title),
      text(size: 8.5pt, fill: c-muted, capitalize(g.goal_type)),
      text(size: 8.5pt, fill: c-muted, capitalize(g.subject)),
      text(size: 9pt, if g.target_value != 0.0 { str(calc.round(g.target_value, digits: 1)) } else { "—" }),
      text(size: 9pt, if g.actual_value != 0.0 { str(calc.round(g.actual_value, digits: 1)) } else { "—" }),
      status-badge(g.status)
    )}
  )
  #v(6pt)
  #text(size: 8pt, fill: c-muted)[
    Status: #h(2pt)
    #box(fill:c-green-bg, inset:(x:5pt,y:2pt), radius:10pt, stroke: 0.5pt+c-green.lighten(40%),
      text(fill:c-green,size:7.5pt,weight:"bold","Exceeds"))
    #h(4pt)
    #box(fill:rgb("#eff6ff"), inset:(x:5pt,y:2pt), radius:10pt, stroke: 0.5pt+c-blue.lighten(40%),
      text(fill:c-blue,size:7.5pt,weight:"bold","Meets"))
    #h(4pt)
    #box(fill:c-amber-bg, inset:(x:5pt,y:2pt), radius:10pt, stroke: 0.5pt+c-amber.lighten(40%),
      text(fill:c-amber,size:7.5pt,weight:"bold","Approaching"))
    #h(4pt)
    #box(fill:c-red-bg, inset:(x:5pt,y:2pt), radius:10pt, stroke: 0.5pt+c-red.lighten(40%),
      text(fill:c-red,size:7.5pt,weight:"bold","Below"))
  ]
]

// ── Section 4: Interventions ──────────────────────────────────────────────────
#section-title("Active Intervention Triggers",
  subtitle: "Students or cohorts flagged as trending toward non-compliance")

#if elixir_data.active_triggers.len() == 0 [
  #rect(
    width: 100%, inset: (x: 16pt, y: 14pt),
    stroke: 0.75pt + rgb("#86efac"),
    fill: c-green-bg,
    radius: 2pt,
    grid(
      columns: (auto, 1fr),
      gutter: 10pt,
      align: horizon,
      text(fill: c-green, size: 14pt, "✓"),
      {
        text(fill: c-green, weight: "bold", size: 9.5pt, "No active interventions")
        linebreak()
        text(fill: c-green, size: 8.5pt, "This school has no active intervention triggers at this time.")
      }
    )
  )
] else [
  #table(
    columns: (1fr, 2fr, 1.4fr, 2fr),
    stroke: (x, y) => if y == 0 { none } else { (bottom: 0.5pt + c-border) },
    inset: (x: 10pt, y: 8pt),
    fill: (x, y) => if y == 0 { c-th-bg } else if calc.odd(y) { white } else { c-row-alt },
    th("Severity"), th("Type"), th("Date"), th("Notes"),
    ..for t in elixir_data.active_triggers {(
      severity-badge(t.severity),
      text(size: 9pt, capitalize(t.trigger_type)),
      text(size: 9pt, fill: c-muted, t.triggered_at),
      text(size: 9pt, fill: c-muted, if t.notes != "" { t.notes } else { "—" })
    )}
  )
]

// ── Signature block ───────────────────────────────────────────────────────────
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
