// Emisint — Board Summary
// One-page, US-Letter-portrait report — Phase 1.1's second distinct visual
// preset (PLAN_betterPDF.md), proving the shared design-system components
// compose into a genuinely different layout, not just a re-skinned copy of
// the 8-page landscape Performance Report. REAL-data-only by design — see
// board_summary_pdf.ex's moduledoc.

#import "/shared/design_system.typ": *

// ── Page layout (portrait, single page — no running header needed) ─────────
#set page(
  paper: "us-letter",
  margin: (top: 0.7in, bottom: 0.7in, left: 0.7in, right: 0.7in),
  footer: context {
    set text(size: 7.5pt, fill: c-muted, font: "Helvetica Neue")
    line(length: 100%, stroke: 0.5pt + c-border)
    v(3pt)
    grid(
      columns: (1fr, auto),
      align: (horizon + left, horizon + right),
      [Confidential — Emisint Academic Performance Module],
      [Generated #elixir_data.generated_on]
    )
  }
)

#set text(font: "Helvetica Neue", size: 9.5pt, fill: c-text)
#set par(leading: 0.6em, spacing: 0.6em)

// ── Header band ──────────────────────────────────────────────────────────
#grid(
  columns: (auto, 1fr, auto),
  gutter: 12pt,
  align: horizon,
  image("/school/emisint_small_logo.png", width: 36pt),
  {
    text(weight: "bold", size: 16pt, fill: c-primary,
      elixir_data.report_year_label + " Board Summary")
    linebreak()
    text(size: 11pt, fill: c-text, disp-str(elixir_data.school.name))
  },
  align(right, text(size: 8pt, fill: c-muted, disp-str(elixir_data.org_name)))
)

#v(4pt)
#line(length: 100%, stroke: 1pt + c-primary)
#v(16pt)

// ── KPI row: School Index / Assessment Participation / Enrollment ─────────
#grid(
  columns: (1fr, 1fr, 1fr),
  gutter: 20pt,
  align(center, {
    text(size: 9pt, weight: "bold", "School Index")
    v(6pt)
    gauge(elixir_data.school_index.value, 100.0, c-accent)
  }),
  align(center, {
    text(size: 9pt, weight: "bold", "Assessment Participation")
    v(6pt)
    gauge(elixir_data.participation.value, 100.0, c-success)
    v(4pt)
    text(size: 7pt, fill: c-muted,
      "Min. Required: " + fmt1(elixir_data.participation.minimum_required) + "%")
  }),
  align(center, {
    v(14pt)
    stat-box("Total Enrollment", fmt-int(elixir_data.enrollment.total))
  })
)

#v(8pt)
#align(center, text(size: 8pt, fill: c-muted,
  "MDE Designated Support Category: " +
  text(weight: "bold", fill: c-text, disp-str(elixir_data.participation.support_category))
))

#section-title("Performance Overview")
#{
  let ov = elixir_data.performance_overview
  grid(
    columns: (1fr, 1fr),
    gutter: 20pt,
    grid(columns: (auto, auto), gutter: 10pt, align: horizon,
      text(size: 9.5pt, weight: "semibold", "Academic Achievement"),
      status-pill(ov.academic_achievement)),
    grid(columns: (auto, auto), gutter: 10pt, align: horizon,
      text(size: 9.5pt, weight: "semibold", "Academic Growth"),
      status-pill(ov.academic_growth))
  )
}

#section-title("Proficiency & Growth Snapshot",
  subtitle: "Current year, weighted by tested enrollment")
#table(
  columns: (1.4fr, 1fr, 1fr, 1fr),
  stroke: 0.4pt + c-border,
  inset: (x: 10pt, y: 7pt),
  fill: (x, y) => if y == 0 { c-th-bg } else if calc.odd(y) { white } else { c-row-alt },
  th("Subject"), th("School Proficiency"), th("State Proficiency"), th("Mean SGP"),
  text(size: 9pt, weight: "semibold", "ELA"),
  align(center, pct-badge(elixir_data.proficiency.school_ela)),
  align(center, pct-badge(elixir_data.proficiency.state_ela)),
  align(center, sgp-badge(elixir_data.sgp.ela)),
  text(size: 9pt, weight: "semibold", "Mathematics"),
  align(center, pct-badge(elixir_data.proficiency.school_math)),
  align(center, pct-badge(elixir_data.proficiency.state_math)),
  align(center, sgp-badge(elixir_data.sgp.math)),
)

#section-title("Student Resident Districts")
#{
  let rd-colors = (c-primary, c-accent, c-border.darken(10%))
  let rd-slices = elixir_data.resident_districts.enumerate().map(((i, r)) => (
    name: r.name, pct: r.pct, color: rd-colors.at(calc.min(i, rd-colors.len() - 1))
  ))

  if rd-slices.len() > 0 {
    grid(columns: (auto, 1fr), gutter: 20pt, align: horizon,
      align(center, pie-chart(rd-slices, radius: 38pt)),
      pie-legend(rd-slices)
    )
  } else {
    text(size: 8.5pt, fill: c-muted, style: "italic",
      "No resident-district data on file for this school.")
  }
}
