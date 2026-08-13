// Emisint — ED% vs. Performance Regression Report
// A focused export of the ESP Portfolio "Regression" tab: same
// Emisint.Assessments.EdRegression calculation as the full Portfolio
// Overview PDF, rendered on its own with bigger charts and a full
// supporting-data table instead of being one small section in a longer report.

#import "/shared/design_system.typ": *

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
          text(fill: c-muted, size: 8pt, elixir_data.agency_name))
      )
    ]
  }
)

#set text(font: "Helvetica Neue", size: 9.5pt, fill: c-text)
#set par(leading: 0.6em, spacing: 0.6em)

// ── Helpers (template-specific — shared ones come from the import above) ────

// Left-accent-bar section heading, distinct from the shared partial's
// centered `section-heading` (School Performance Report style) — this one
// intentionally shadows it for this template's own visual language.
#let section-heading(title, subtitle: "") = {
  v(10pt)
  grid(columns: (4pt, 1fr), gutter: 10pt,
    rect(width: 4pt, height: if subtitle != "" { 30pt } else { 20pt }, fill: c-accent, radius: 1pt),
    {
      text(weight: "bold", size: 12pt, fill: c-primary, title)
      if subtitle != "" {
        linebreak()
        text(size: 8.5pt, fill: c-muted, subtitle)
      }
    }
  )
  v(8pt)
}

#let big-regression-chart(y-label, points, threshold-ed, threshold-val, slope, intercept, y-unit) = {
  regression-chart(y-label, points, threshold-ed, threshold-val, slope, intercept, y-unit,
    chart-h: 220pt, numbered: true, dot-radius: 6pt)
  v(4pt)
  text(size: 7pt, fill: c-muted,
    "X: Economically Disadvantaged % · Y: " + y-label +
    " · gray crosshair: statewide average · line: least-squares trend · " +
    "dot number matches the # column in the supporting-data table below")
}

// Supporting-data table: one row per school, numbered to match its dot.
#let data-table(points, value-label: "Performance") = {
  table(
    columns: (34pt, 2.6fr, 1fr, 1fr, 1.4fr),
    stroke: 0.4pt + c-border,
    inset: (x: 8pt, y: 5pt),
    fill: (x, y) => if y == 0 { c-th-bg } else if calc.odd(y) { white } else { c-row-alt },
    th("#"), th("School"), th("ED %"), th(value-label), th("Classification"),
    ..points.map(p => (
      text(size: 8pt, fill: c-muted, str(p.idx)),
      text(size: 8pt, disp-str(p.school_name)),
      text(size: 8pt, fmt1(p.ed_pct) + "%"),
      text(size: 8pt, fmt1(p.value)),
      quadrant-badge(p.quadrant),
    )).flatten()
  )
}

#let excluded-table(excluded, value-label: "Performance") = {
  if excluded.len() > 0 {
    v(8pt)
    text(size: 8pt, fill: c-muted, weight: "bold",
      upper(str(excluded.len()) + " school(s) excluded — missing ED% or " + lower(value-label) + " data"))
    v(4pt)
    table(
      columns: (2.6fr, 1fr, 1fr),
      stroke: 0.4pt + c-border,
      inset: (x: 8pt, y: 4pt),
      fill: (x, y) => if y == 0 { c-th-bg } else if calc.odd(y) { white } else { c-row-alt },
      th("School"), th("ED %"), th(value-label),
      ..excluded.map(s => (
        text(size: 7.5pt, fill: c-muted, disp-str(s.school_name)),
        text(size: 7.5pt, fill: c-muted, fmt1(s.ed_pct)),
        text(size: 7.5pt, fill: c-muted, fmt1(s.value)),
      )).flatten()
    )
  }
}

// ══════════════════════════════════════════════════════════════════════════
// PAGE 1 — Header + charts
// ══════════════════════════════════════════════════════════════════════════

#grid(columns: (1fr, auto), align: (left + bottom, right + bottom),
  {
    text(weight: "bold", size: 19pt, fill: c-primary, disp-str(elixir_data.agency_name))
    linebreak()
    text(size: 10.5pt, fill: c-text,
      "Economically Disadvantaged % vs. Performance — " + disp-str(elixir_data.school_year))
  },
  align(right, {
    text(size: 8pt, fill: c-muted, "Generated " + disp-str(elixir_data.report_date))
    linebreak()
    text(size: 8pt, fill: c-muted, str(int(to-num(elixir_data.school_count))) + " schools in portfolio")
  })
)

#v(6pt)
#line(length: 100%, stroke: 1.3pt + c-primary)
#v(6pt)

#text(size: 8.5pt, fill: c-muted, [
  Each dot is one school in this portfolio, numbered to match its row in the supporting-data
  table on the following pages (a static PDF can't do hover tooltips the way the live dashboard
  can, so the number is the paper equivalent). X-axis is the share of economically disadvantaged
  students enrolled; Y-axis is M-STEP/PSAT or SAT performance. The gray crosshair marks the
  statewide average on each axis, and the line is a least-squares linear regression fit across
  these schools.
])

#v(10pt)

#let mstep-points = with-index(elixir_data.mstep.points)
#let sat-points = with-index(elixir_data.sat.points)

#grid(columns: (1fr, 1fr), gutter: 26pt,
  {
    align(center, text(size: 10pt, weight: "bold", "M-STEP/PSAT vs. ED%"))
    v(6pt)
    big-regression-chart("M-STEP/PSAT Proficiency %", mstep-points,
      elixir_data.mstep.threshold_ed_pct, elixir_data.mstep.threshold_value,
      elixir_data.mstep.slope, elixir_data.mstep.intercept, elixir_data.mstep.y_unit)
  },
  {
    align(center, text(size: 10pt, weight: "bold", "SAT vs. ED%"))
    v(6pt)
    big-regression-chart("SAT Score", sat-points,
      elixir_data.sat.threshold_ed_pct, elixir_data.sat.threshold_value,
      elixir_data.sat.slope, elixir_data.sat.intercept, elixir_data.sat.y_unit)
  }
)

#v(10pt)
#text(size: 7.5pt, fill: c-muted, [
  Classification key: #quadrant-badge("green") above-average ED% and above-average performance
  #h(6pt) #quadrant-badge("orange") performance roughly in line with what ED% alone would predict
  #h(6pt) #quadrant-badge("red") below-average ED% and below-average performance
])

#pagebreak()

// ══════════════════════════════════════════════════════════════════════════
// PAGE 2+ — Supporting data
// ══════════════════════════════════════════════════════════════════════════

#section-heading("M-STEP/PSAT vs. ED% — Supporting Data",
  subtitle: str(mstep-points.len()) + " schools, sorted by performance")
#data-table(mstep-points)
#excluded-table(elixir_data.mstep.excluded)

#pagebreak()

#section-heading("SAT vs. ED% — Supporting Data",
  subtitle: str(sat-points.len()) + " schools, sorted by performance")
#data-table(sat-points)
#excluded-table(elixir_data.sat.excluded)
