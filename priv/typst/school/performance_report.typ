// Emisint — School Performance Report
// 8-page landscape report matching the target design in PLAN_betterPDF.md
// ("Target Report Design (Reference Layout)" section).

#import "/shared/design_system.typ": *

// Local aliases so this template's body (written against the original
// standalone color names) didn't need a full rewrite during the Phase 0
// design-system migration — see PLAN_betterPDF.md.
#let c-orange   = c-warning
#let c-green    = c-success
#let c-green-bg = c-success-bg
#let c-amber    = c-warning
#let c-amber-bg = c-warning-bg
#let c-red      = c-error
#let c-red-bg   = c-error-bg

// ── Page layout (landscape) ───────────────────────────────────────────────────
#set page(
  paper: "us-letter",
  flipped: true,
  margin: (top: 0.5in, bottom: 0.55in, left: 0.55in, right: 0.55in),
  footer: context {
    if counter(page).get().first() > 1 [
      #grid(
        columns: (auto, 1fr, auto),
        align: (horizon + left, horizon, horizon + right),
        box(fill: c-primary, inset: (x: 10pt, y: 4pt), radius: 1pt,
          text(fill: white, weight: "bold", size: 9pt, str(counter(page).display()))),
        [],
        box(fill: c-th-bg, inset: (x: 10pt, y: 4pt),
          text(fill: c-muted, size: 8pt, elixir_data.org_name))
      )
    ]
  }
)

#set text(font: "Helvetica Neue", size: 9.5pt, fill: c-text)
#set par(leading: 0.6em, spacing: 0.6em)

// ── Helpers: text / layout (template-specific, kept local) ──────────────────
#let page-title-block(subtitle: "") = align(center, {
  text(weight: "bold", size: 13pt, fill: c-primary,
    elixir_data.report_year_label + " School Performance Report")
  linebreak()
  text(size: 10pt, fill: c-text, disp-str(elixir_data.school.name))
  if subtitle != "" {
    linebreak()
    v(2pt)
    text(size: 8.5pt, fill: c-muted, subtitle)
  }
})

// ══════════════════════════════════════════════════════════════════════════
// PAGE 1 — Cover
// ══════════════════════════════════════════════════════════════════════════

#grid(
  columns: (auto, 1fr, 26pt),
  gutter: 0pt,
  {
    grid(columns: (34pt, auto), gutter: 10pt, align: horizon,
      image("/school/emisint_small_logo.png", width: 30pt),
      text(size: 9pt, fill: c-muted, weight: "semibold", elixir_data.org_name)
    )
  },
  align(center, {
    v(6pt)
    text(weight: "bold", size: 20pt, fill: c-primary,
      elixir_data.report_year_label + " School Performance Report")
    linebreak()
    v(4pt)
    text(size: 13pt, fill: c-text, disp-str(elixir_data.school.name))
  }),
  align(right, box(fill: c-primary, width: 100%, height: 100pt, inset: 6pt,
    align(center + horizon,
      rotate(-90deg, reflow: true,
        text(fill: white, size: 8pt, weight: "bold", tracking: 1.5pt,
          upper(disp-str(elixir_data.org_name)))))))
)

#v(14pt)
#decorative-band(elixir_data.school.name, height: 190pt)
#v(10pt)

#grid(
  columns: (1fr, 1fr),
  gutter: 24pt,
  {
    text(size: 8pt, fill: c-muted, weight: "bold", upper("School Information"))
    v(6pt)
    text(size: 9pt, disp-str(elixir_data.school.street))
    linebreak()
    text(size: 9pt,
      disp-str(elixir_data.school.city) + ", " +
      disp-str(elixir_data.school.state) + " " + disp-str(elixir_data.school.zip))
    v(6pt)
    grid(columns: (auto, 1fr), gutter: 8pt, row-gutter: 4pt,
      text(size: 8.5pt, weight: "bold", "Grades Served:"),
      text(size: 8.5pt, disp-str(elixir_data.school.grades_served)),
      text(size: 8.5pt, weight: "bold", "Contract Grades:"),
      text(size: 8.5pt, disp-str(elixir_data.school.contract_grades)),
      text(size: 8.5pt, weight: "bold", "Year Opened:"),
      text(size: 8.5pt, disp-str(elixir_data.school.year_opened)),
    )
  },
  grid(columns: (4pt, 1fr), gutter: 10pt,
    rect(width: 4pt, height: 60pt, fill: c-accent, radius: 1pt),
    {
      text(size: 8pt, fill: c-muted, weight: "bold", upper("School's Mission"))
      v(6pt)
      text(size: 9pt, disp-str(elixir_data.school.mission))
    }
  )
)

#pagebreak()

// ══════════════════════════════════════════════════════════════════════════
// PAGE 2 — Governance and summary status
// ══════════════════════════════════════════════════════════════════════════

#rect(width: 100%, fill: c-primary, inset: (x: 16pt, y: 12pt),
  align(center, {
    text(fill: white, weight: "bold", size: 12pt,
      elixir_data.report_year_label + " School Performance Report")
    linebreak()
    text(fill: white.transparentize(15%), size: 9.5pt, disp-str(elixir_data.school.name))
  })
)

#v(14pt)
#grid(columns: (1fr, 1fr), gutter: 24pt,
  {
    text(size: 8pt, fill: c-muted, weight: "bold", upper("Current Contract Term Length"))
    v(4pt)
    text(size: 15pt, weight: "bold", fill: c-text, disp-str(elixir_data.contract.term_length))
  },
  {
    text(size: 8pt, fill: c-muted, weight: "bold", upper("Contract Expiration Year"))
    v(4pt)
    text(size: 15pt, weight: "bold", fill: c-text, disp-str(elixir_data.contract.expiration_year))
  }
)

#v(12pt)
#text(size: 8pt, fill: c-muted, weight: "bold", upper("Educational Service Provider"))
#v(3pt)
#text(size: 10pt, weight: "semibold", disp-str(elixir_data.contract.esp_name))

#v(12pt)
#table(
  columns: (2fr, 1.4fr, 1fr, 1fr),
  stroke: 0.4pt + c-border,
  inset: (x: 10pt, y: 6pt),
  fill: (x, y) => if y == 0 { c-th-bg } else if calc.odd(y) { white } else { c-row-alt },
  th("Name"), th("Board Role"), th("Appointed"), th("Term Ends"),
  ..elixir_data.board_members.map(m => (
    text(size: 8.5pt, disp-str(m.name)),
    text(size: 8.5pt, fill: c-muted, disp-str(m.role)),
    text(size: 8.5pt, fill: c-muted, disp-str(m.appointed)),
    text(size: 8.5pt, fill: c-muted, disp-str(m.term_ends)),
  )).flatten()
)

#v(10pt)
#decorative-band(elixir_data.school.name, height: 70pt)

#section-heading(elixir_data.report_year_label + " School Performance Overview")

#align(center, {
  let ov = elixir_data.performance_overview
  let rows = (
    ("Compliance Reporting Condition", ov.compliance_reporting),
    ("Financial Reporting Condition", ov.financial_reporting),
    ("Academic Achievement (M-STEP/PSAT)", ov.academic_achievement),
    ("Academic Growth (ELA, Math)", ov.academic_growth),
  )
  for (label, rating) in rows {
    grid(columns: (240pt, auto), gutter: 16pt, align: (right + horizon, left + horizon),
      text(size: 9.5pt, weight: "semibold", label),
      status-pill(rating)
    )
    v(8pt)
  }
})

#pagebreak()

// ══════════════════════════════════════════════════════════════════════════
// PAGE 3 — Enrollment and demographics
// ══════════════════════════════════════════════════════════════════════════

#page-title-block()
#section-heading("School Characteristics")

#let rd-colors = (c-primary, c-accent, c-border.darken(10%))
#let rd-slices = elixir_data.resident_districts.enumerate().map(((i, r)) => (
  name: r.name, pct: r.pct, color: rd-colors.at(calc.min(i, rd-colors.len() - 1))
))

#grid(columns: (1fr, 1fr), gutter: 28pt,
  {
    align(center, text(size: 9pt, weight: "bold", "Student Resident Districts"))
    v(8pt)
    grid(columns: (auto, 1fr), gutter: 20pt, align: horizon,
      align(center, pie-chart(rd-slices)),
      pie-legend(rd-slices)
    )
  },
  {
    align(center, text(size: 9pt, weight: "bold", "Subgroup Enrollment and Attendance"))
    v(10pt)
    horizontal-bars(elixir_data.enrollment.subgroups, color: c-muted.lighten(10%))
  }
)

#v(6pt)
#align(center, text(size: 9pt, weight: "bold", "5 Year Enrollment Trend"))
#v(4pt)
#line-chart((
  (name: "Enrollment", color: c-accent, points: elixir_data.enrollment.trend),
), height: 92pt)

#v(6pt)
#align(center, text(size: 9pt, weight: "bold", "Enrollment by Grade and Year"))
#v(4pt)
#heatmap-table(
  elixir_data.enrollment.by_grade.years,
  elixir_data.enrollment.by_grade.rows,
  elixir_data.enrollment.by_grade.totals
)
#v(3pt)
#text(size: 7pt, fill: c-muted, "* Data suppression    ** Refer to year opened on cover.")

#pagebreak()

// ══════════════════════════════════════════════════════════════════════════
// PAGE 4 — Peer schools and index
// ══════════════════════════════════════════════════════════════════════════

#page-title-block()
#section-heading("Roster of Statistically Similar Schools")

#table(
  columns: (1fr, 3fr),
  stroke: 0.4pt + c-border,
  inset: (x: 10pt, y: 6pt),
  fill: (x, y) => if y == 0 { c-th-bg } else if calc.odd(y) { white } else { c-row-alt },
  th("Distance in Miles"), th("Peer School Name"),
  ..elixir_data.peer_roster.map(p => (
    text(size: 8.5pt, fmt1(p.distance)),
    text(size: 8.5pt, disp-str(p.name)),
  )).flatten()
)
#v(3pt)
#{
  let is-sample = elixir_data.peer_roster_is_sample
  let is-sample = if type(is-sample) == str { is-sample == "true" } else { is-sample }
  if is-sample [
    #text(size: 7pt, fill: c-muted, style: "italic",
      "Sample roster — no MDE SSS peer-group data on file for this school.")
  ] else [
    #text(size: 7pt, fill: c-muted,
      "Source: MDE Statistically Similar Schools grouping. Distance in miles is not part of the MDE SSS file and is not shown.")
  ]
}

#v(11pt)
#grid(columns: (1fr, 1fr), gutter: 30pt, align: center,
  {
    text(size: 9.5pt, weight: "bold", "School Index")
    v(8pt)
    gauge(elixir_data.school_index.value, 100.0, c-accent)
    v(6pt)
    text(size: 7.5pt, fill: c-muted,
      "Minimum Threshold: " + fmt1(elixir_data.school_index.minimum_threshold) + "*")
  },
  {
    text(size: 9.5pt, weight: "bold", "Assessment Participation")
    v(8pt)
    gauge(elixir_data.participation.value, 100.0, c-green)
    v(6pt)
    text(size: 7.5pt, fill: c-muted,
      "Minimum Required: " + fmt1(elixir_data.participation.minimum_required) + "%**")
  }
)

#v(8pt)
#align(center, text(size: 9pt,
  "MDE Designated Support Category: " +
  text(weight: "bold", disp-str(elixir_data.participation.support_category))
))

#v(10pt)
#text(size: 7pt, fill: c-muted, [
  \* The School Index Minimum Threshold is the composite accountability score below which MDE
  flags a school for additional support, per the state's federally-approved accountability system.\
  \*\* Assessment Participation reflects the share of enrolled, eligible students who took the
  required state assessments; federal ESSA rules set a 95% minimum participation rate.
])

#v(8pt)
#decorative-band(elixir_data.school.name, height: 80pt)

#pagebreak()

// ══════════════════════════════════════════════════════════════════════════
// PAGE 5 — Contract performance trends
// ══════════════════════════════════════════════════════════════════════════

#page-title-block(subtitle: "")
#section-heading("Charter Contract Academic Performance Trends")

#text(size: 8.5pt, [
  Academic outcomes over time are central to this school's contract renewal. Boards and school
  leaders are encouraged to use the trends below as a starting point for discussing progress
  against Schedule 7-1 goals and peer-relative performance. See the Appendix for how each measure
  is calculated.
])

#v(10pt)
#align(center, text(size: 9pt, weight: "bold",
  "Achievement Performance Compared to Peer Schools Over Time"
) + text(size: 8pt, fill: c-muted, "  (M-STEP/PSAT)"))
#v(6pt)
#line-chart((
  (name: "vs. Peer Schools", color: c-accent, points: elixir_data.achievement_trend),
))

#v(10pt)
#align(center, text(size: 9pt, weight: "bold",
  "Growth Performance Compared to Peer Schools Over Time"))
#v(6pt)
#grid(columns: (1fr, 1fr), gutter: 24pt,
  {
    align(center, text(size: 8.5pt, fill: c-orange, weight: "bold", "ELA"))
    v(4pt)
    line-chart((
      (name: "ELA", color: c-orange, points: elixir_data.growth_trend.ela),
    ))
  },
  {
    align(center, text(size: 8.5pt, fill: c-accent, weight: "bold", "Math"))
    v(4pt)
    line-chart((
      (name: "Math", color: c-accent, points: elixir_data.growth_trend.math),
    ))
  }
)

#v(6pt)
#align(center, text(size: 8pt, fill: c-text,
  "Current-year Mean SGP (actual): " +
  text(weight: "bold", fill: c-orange, "ELA " + fmt1(elixir_data.current_sgp.ela)) +
  "  ·  " +
  text(weight: "bold", fill: c-accent, "Math " + fmt1(elixir_data.current_sgp.math)) +
  text(fill: c-muted, "  (1–99 scale; 50 = typical growth)")
))

#v(6pt)
#text(size: 7pt, fill: c-muted, [
  Growth data may be limited in years with missing or low-participation state testing; elementary
  grades (K–2) do not receive a state growth (SGP) score.\
  \* Data suppression
])

#pagebreak()

// ══════════════════════════════════════════════════════════════════════════
// PAGE 6 — Proficiency trends
// ══════════════════════════════════════════════════════════════════════════

#page-title-block()
#section-heading("M-STEP Proficiency Trends by Subject")

#let prof = elixir_data.proficiency_trend

#grid(columns: (1fr, 1fr), gutter: 26pt,
  {
    align(center, {
      text(size: 9pt, weight: "bold", fill: c-primary, "M-STEP/PSAT ")
      text(size: 9pt, weight: "bold", fill: c-orange, "ELA")
      text(size: 9pt, weight: "bold", fill: c-primary, " Proficiency")
    })
    v(4pt)
    chart-legend((
      (name: "School", color: c-orange),
      (name: "State", color: c-muted),
      (name: "Peer Schools", color: c-text),
    ))
    v(4pt)
    line-chart((
      (name: "School", color: c-orange, points: prof.ela.school),
      (name: "State", color: c-muted, points: prof.ela.state),
      (name: "Peer Schools", color: c-text, points: prof.ela.peer),
    ))
  },
  {
    align(center, {
      text(size: 9pt, weight: "bold", fill: c-primary, "M-STEP/PSAT ")
      text(size: 9pt, weight: "bold", fill: c-accent, "Math")
      text(size: 9pt, weight: "bold", fill: c-primary, " Proficiency")
    })
    v(4pt)
    chart-legend((
      (name: "School", color: c-accent),
      (name: "State", color: c-muted),
      (name: "Peer Schools", color: c-text),
    ))
    v(4pt)
    line-chart((
      (name: "School", color: c-accent, points: prof.math.school),
      (name: "State", color: c-muted, points: prof.math.state),
      (name: "Peer Schools", color: c-text, points: prof.math.peer),
    ))
  }
)

#v(8pt)
#text(size: 7pt, fill: c-muted, "* Data suppression")

#pagebreak()

// ══════════════════════════════════════════════════════════════════════════
// PAGE 7 — Appendix: academic and compliance definitions
// ══════════════════════════════════════════════════════════════════════════

#align(center, {
  text(size: 12pt, weight: "bold", fill: c-primary, "Appendix")
  linebreak()
  text(size: 8pt, fill: c-muted,
    elixir_data.report_year_label + " School Performance Report — " + disp-str(elixir_data.school.name))
})
#v(14pt)

#text(weight: "bold", size: 10pt, fill: c-primary, "Academic Achievement:")
#v(4pt)
#text(size: 8.5pt, [
  Academic Achievement reflects a school's state assessment (M-STEP, PSAT, SAT) proficiency
  rates relative to state and peer benchmarks.
])
#v(6pt)
#for (term, desc) in (
  ("Exceeds Standard:", "School proficiency rates meaningfully outperform both state and peer-school averages."),
  ("Meets Standard:", "School proficiency rates are in line with state and peer-school averages."),
  ("Does Not Meet Standard:", "School proficiency rates fall meaningfully below state and peer-school averages."),
) [
  #text(weight: "bold", size: 8.5pt, term) #text(size: 8.5pt, " " + desc)
  #v(4pt)
]

#v(10pt)
#text(weight: "bold", size: 10pt, fill: c-primary, "Academic Growth:")
#v(4pt)
#text(size: 8.5pt, [
  Academic Growth is measured using Student Growth Percentile (SGP), which compares each
  student's year-over-year progress to that of academic peers statewide with a similar score
  history, then aggregates to a school-level median or mean SGP (1–99 scale; 50 = typical growth).
])

#v(10pt)
#text(weight: "bold", size: 10pt, fill: c-primary, "Compliance Reporting Condition Definitions:")
#v(4pt)
#for (term, desc) in (
  ("Exceeds Standard:", "All required state and authorizer compliance reports were filed accurately and on time."),
  ("Meets Standard:", "Required compliance reports were filed with only minor, promptly-corrected issues."),
  ("Does Not Meet Standard:", "One or more required compliance reports were missing, late, or materially inaccurate."),
) [
  #text(weight: "bold", size: 8.5pt, term) #text(size: 8.5pt, " " + desc)
  #v(4pt)
]

#pagebreak()

// ══════════════════════════════════════════════════════════════════════════
// PAGE 8 — Appendix: financial condition and test list
// ══════════════════════════════════════════════════════════════════════════

#align(center, {
  text(size: 12pt, weight: "bold", fill: c-primary, "Appendix")
  linebreak()
  text(size: 8pt, fill: c-muted,
    elixir_data.report_year_label + " School Performance Report — " + disp-str(elixir_data.school.name))
})
#v(14pt)

#text(weight: "bold", size: 10pt, fill: c-primary, "Financial Condition Definitions:")
#v(4pt)
#for (term, desc) in (
  ("Exceeds Standard:", "The school maintains strong reserves, a balanced budget, and no material audit findings."),
  ("Meets Standard:", "The school's financial position is stable with no significant concerns."),
  ("Does Not Meet Standard:", "The school shows signs of financial distress, such as declining reserves or audit findings."),
) [
  #text(weight: "bold", size: 8.5pt, term) #text(size: 8.5pt, " " + desc)
  #v(4pt)
]

#v(14pt)
#text(weight: "bold", size: 10pt, fill: c-primary, "Michigan State Tests by Grade:")
#v(6pt)
#table(
  columns: (1.2fr, 1.4fr, 2fr),
  stroke: 0.4pt + c-border,
  inset: (x: 10pt, y: 6pt),
  fill: (x, y) => if y == 0 { c-th-bg } else if calc.odd(y) { white } else { c-row-alt },
  th("Subject"), th("Grades"), th("Test(s)"),
  text(size: 8.5pt, "ELA"), text(size: 8.5pt, fill: c-muted, "3–8, 11"), text(size: 8.5pt, "M-STEP (3–8), PSAT (8, 10), SAT (11)"),
  text(size: 8.5pt, "Math"), text(size: 8.5pt, fill: c-muted, "3–8, 11"), text(size: 8.5pt, "M-STEP (3–8), PSAT (8, 10), SAT (11)"),
  text(size: 8.5pt, "Social Studies"), text(size: 8.5pt, fill: c-muted, "5, 8, 11"), text(size: 8.5pt, "M-STEP"),
  text(size: 8.5pt, "Science"), text(size: 8.5pt, fill: c-muted, "5, 8, 11"), text(size: 8.5pt, "M-STEP"),
)
