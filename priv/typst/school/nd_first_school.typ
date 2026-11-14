// Emisint — ND First individual school report
// Data: elixir_data (see Emisint.Reports.School.NdFirstSchoolPdf). All values
// arrive as strings already formatted by the shared dashboard rules.

#let c-text   = rgb("#1e293b")
#let c-muted  = rgb("#64748b")
// Goal lines in tinted table cells: darker than muted for contrast on the tint.
#let c-note   = rgb("#475569")
#let c-border = rgb("#e2e8f0")
#let c-th-bg  = rgb("#f1f5f9")
#let c-alt    = rgb("#f8fafc")
#let c-accent = rgb("#1d4ed8")
// Rubric, goal-status and (optional) state-comparison text colors; each is at least 5.4:1 on white and on
// the alternating row fill (WCAG AA).
#let c-success = rgb("#067647")
#let c-info    = rgb("#175cd3")
#let c-warning = rgb("#8a5300")
#let c-error   = rgb("#b42318")

#let d = elixir_data
#let s(x) = if x == none or x == "" { "—" } else { x }
// Booleans may arrive as strings from Elixir (see the typst skill).
#let truthy(x) = x == true or x == "true"

#set document(title: d.school.name + " — " + d.report.title)
#set text(font: "Helvetica Neue", size: 8.5pt, fill: c-text)
#set par(leading: 0.55em)
// Keep each table row on one page; headers repeat on continuation pages.
#set table.cell(breakable: false)
#set page(
  paper: "us-letter",
  margin: (top: 0.8in, bottom: 0.75in, left: 0.7in, right: 0.7in),
  header: context {
    if counter(page).get().first() > 1 [
      #set text(size: 7.5pt, fill: c-muted)
      #grid(
        columns: (1fr, auto),
        [#d.school.name · ND First school report · #d.report.period],
        [Page #counter(page).display() of #counter(page).final().first()]
      )
      #v(2pt)
      #line(length: 100%, stroke: 0.5pt + c-border)
    ]
  },
  footer: context [
    #set text(size: 7pt, fill: c-muted)
    #grid(
      columns: (1fr, auto),
      [Generated #d.report.generated_at by #d.report.generated_by],
      [Page #counter(page).display()]
    )
  ],
)

#let th(body) = text(weight: "bold", size: 7.5pt, fill: c-muted, upper(body))
#let section(title) = {
  v(10pt)
  block(sticky: true, below: 6pt, text(size: 12pt, weight: "bold", fill: c-text, title))
}
// Kept on the same page as the table or note that follows it.
#let subhead(body) = block(sticky: true, above: 8pt, below: 4pt, body)
#let note(body) = text(size: 7.5pt, fill: c-muted, body)
// A table's heading and short notes, kept with the table's header and first
// rows (sticky blocks move to the next page together with what follows).
#let lead(title, notes) = block(sticky: true, above: 10pt, below: 4pt, width: 100%)[
  #title
  #for n in notes [ \ #note(n)]
]
// Starts what follows on the next page unless `body` (measured at the
// current width) fits in the space left on this page. Used to keep a table's
// heading, notes, header and first rows together without a page break.
#let keep-together(body) = layout(size => {
  let h = measure(block(width: size.width, body)).height
  block(breakable: false, above: 0pt, below: 0pt, height: h, width: 100%)
  v(-h)
})
// A list whose items never split across pages.
#let notes-list(items) = list(spacing: 0.45em, ..items.map(n => block(breakable: false, note(n))))
// Tones arrive from Elixir as "success", "info", "warning", "error" or
// "neutral" (Emisint.Reports.School.NdFirstSchoolPdf); neutral stays plain.
#let tone-colors = (success: c-success, info: c-info, warning: c-warning, error: c-error)
#let toned(tone, body) = if tone in tone-colors {
  text(fill: tone-colors.at(tone), weight: "semibold", body)
} else { body }
// An implementation rating as a status badge: rubric text color on a light
// tint of the same color (text stays at or above 4.9:1 on the tint).
#let rating-badge(tone, body) = if tone in tone-colors {
  let c = tone-colors.at(tone)
  box(fill: c.lighten(90%), stroke: 0.5pt + c.lighten(60%), inset: (x: 3pt, y: 1.5pt), radius: 2pt,
    text(fill: c, weight: "semibold", body))
} else { body }

// A published state value compared with North Dakota (or, for % tested, the
// 95% participation requirement): a light tint of the status color behind the
// value, and the short label (same wording as the dashboard) beneath it, so
// the status reads without color. Tones arrive as "success", "error",
// "warning", "neutral" (matches the state: outlined), "muted" (gray: not
// compared) or "none" (no comparison).
#let mark-symbol = (success: "✓", error: "×", warning: "≈", neutral: "=", muted: "–")
// The benchmark the value was compared with (e.g. "ND 25%") follows the
// label, since a printed page has no tooltips.
#let cmp-cell(c) = {
  let bench = c.at("bench", default: "")
  let body = [#c.text#if c.label != "" [ \ #text(size: 6.5pt, fill: if c.tone in tone-colors { tone-colors.at(c.tone) } else { c-muted }, weight: if c.tone in tone-colors { "semibold" } else { "regular" }, mark-symbol.at(c.tone, default: "") + " " + c.label)]#if bench != "" [ \ #text(size: 6.5pt, fill: c-muted, bench)]]
  if c.tone in tone-colors {
    block(width: 100%, fill: tone-colors.at(c.tone).lighten(88%), inset: (x: 2pt, y: 1.5pt), radius: 1.5pt, body)
  } else if c.tone == "neutral" {
    block(width: 100%, stroke: 0.6pt + c-muted, inset: (x: 2pt, y: 1.5pt), radius: 1.5pt, body)
  } else { body }
}
// A published value in the main result tables with its matching school goal:
// "success" (Meets goal) or "error" (Below goal) tints the cell; anything
// else stays plain. The status label and the goal with its targets follow,
// since a printed page has no tooltips. % tested arrives with fill "false":
// its 95% participation label is text only, never a goal status.
// Cell values and notes never break inside "20%–29%", "18-month", "G2-M3" or
// "2024-2025" (a word joiner follows each hyphen and en dash), and a value
// stays on the line of its label ("target: 43"), and each "·" part of the goal line starts its
// own line, so narrow cells wrap at word boundaries only.
#let unbroken(s) = s.replace("-", "-\u{2060}").replace("–", "–\u{2060}").replace(": ", ":\u{00A0}")
#let cell-note(fill, body) = text(size: 7pt, fill: fill, body)
#let goal-cell(c) = {
  let filled = truthy(c.fill)
  let color = if c.tone in tone-colors { tone-colors.at(c.tone) } else { c-muted }
  let body = par(leading: 0.45em)[#unbroken(c.text)#if c.label != "" [ \ #cell-note(color, text(weight: if c.tone in tone-colors { "semibold" } else { "regular" }, mark-symbol.at(c.tone, default: "–") + " " + unbroken(c.label)))]#if c.caveat != "" [ \ #cell-note(c-muted, emph(unbroken(c.caveat)))]#if c.line != "" { for part in c.line.split(" · ") [ \ #cell-note(c-note, unbroken(part))] }]
  if filled and c.tone in tone-colors {
    block(width: 100%, fill: color.lighten(88%), inset: (x: 2pt, y: 1.5pt), radius: 1.5pt, body)
  } else if filled and c.tone == "muted" {
    block(width: 100%, fill: rgb("#eef1f5"), inset: (x: 2pt, y: 1.5pt), radius: 1.5pt, body)
  } else { body }
}
#let swatch(tone) = if tone in tone-colors {
  box(width: 7pt, height: 7pt, radius: 1pt, fill: tone-colors.at(tone).lighten(88%), stroke: 0.5pt + tone-colors.at(tone))
} else if tone == "neutral" {
  box(width: 7pt, height: 7pt, radius: 1pt, stroke: 0.6pt + c-muted)
} else { box(width: 7pt, height: 7pt, radius: 1pt, fill: rgb("#eef1f5"), stroke: 0.5pt + c-border) }

#let data-table(columns: (), header: (), rows: ()) = table(
  columns: columns,
  stroke: (x, y) => (bottom: 0.4pt + c-border),
  fill: (x, y) => if y == 0 { c-th-bg } else if calc.even(y) { c-alt } else { none },
  inset: (x: 4pt, y: 4pt),
  align: left + top,
  table.header(repeat: true, ..header.map(th)),
  ..rows.flatten(),
)

// ── Title block ──────────────────────────────────────────────────────────────
#text(size: 18pt, weight: "bold", d.school.name)
#v(-4pt)
#text(size: 10pt, fill: c-muted)[#d.school.district · #d.school.state_id · Grades: #d.school.grades]

#v(6pt)
#block(
  width: 100%,
  inset: 8pt,
  radius: 4pt,
  stroke: 0.5pt + c-border,
  grid(
    columns: (auto, 1fr),
    row-gutter: 3pt,
    column-gutter: 10pt,
    [*Report*], [#d.report.title — #d.school.plan],
    [*Reporting period*], [#d.report.period (#d.report.period_scope)],
    [*State results filters*], [#d.report.state_year · #d.report.state_type assessment · #d.report.state_subgroup#d.report.goal_reference_text],
    [*Generated*], [#d.report.generated_at by #d.report.generated_by],
  ),
)

// Participant scope (district participant or building); empty for a single school.
#if d.scope.note != "" [
  #v(4pt)
  #block(width: 100%, inset: 6pt, radius: 4pt, fill: rgb("#eef4fb"), note(d.scope.note))
]
#if d.scope.provisional != "" [
  #v(3pt)
  #block(width: 100%, inset: 6pt, radius: 4pt, fill: rgb("#fdf3e1"), stroke: 0.5pt + rgb("#d9a441"))[*Workbook scope provisional.* #note(d.scope.provisional)]
]

// A building's report omits the workbook goals, seasonal averages and
// payment: they belong to its participant (district) report.
#let building = d.scope.kind == "building"

// ── Summary ──────────────────────────────────────────────────────────────────
#if not building [
#section("Summary")
#grid(
  columns: (1fr, 1fr, 1.4fr),
  column-gutter: 8pt,
  ..d.averages.map(a => block(
    inset: 7pt,
    radius: 4pt,
    stroke: 0.5pt + c-border,
    width: 100%,
    [#th(a.category + " · " + d.report.period) \ #text(size: 13pt, weight: "bold", a.average) \ #note(a.coverage)],
  )),
  block(
    inset: 7pt,
    radius: 4pt,
    stroke: 0.5pt + c-border,
    width: 100%,
    [#th("Current-ratings preview" + if d.payment.preview.terms_label != "" { " · " + d.payment.preview.terms_label } else { "" }) \
      #text(size: 11pt, weight: "bold", d.payment.preview.headline) \
      #note(d.payment.preview.basis) \
      #note(d.payment.preview.note)],
  ),
)

#v(4pt)
#subhead[*#d.payment.preview.title*]
#note[#d.payment.preview.note It applies the payment formula and completeness rule to this report's reporting period's current implementation ratings, as if they were review ratings. It is not a formal-review estimate; nothing is recorded, and no other period is used when ratings are missing.]
#if d.payment.preview.reason != "" [
  #v(2pt)
  #note(d.payment.preview.reason)
]
#if d.payment.preview.rows.len() > 0 [
  #v(2pt)
  #data-table(
    columns: (0.9fr, 1.3fr, 1.3fr, 0.8fr, 0.8fr, 0.8fr, 2fr),
    header: ("Checkpoint", "Systems average", "Student Outcome average", "Weights", "Weighted score", "Allocation", "Preview payment"),
    rows: d.payment.preview.rows.map(r => (r.label, r.systems, r.outcomes, r.weights, r.weighted, r.allocation, r.payment)),
  )
]

#v(4pt)
#subhead[*Formal review estimates · #d.payment.label*]
#note[#d.payment.terms_summary Only formal 18- and 36-month review ratings count; this is separate from the current-ratings preview above. The calculation and averages are in the appendix.]
#v(2pt)
#data-table(
  columns: (1fr, 1.2fr, 0.8fr, 2.4fr),
  header: ("Checkpoint", "Weights (Systems / Student Outcomes)", "Allocation", "Estimated payment"),
  rows: d.payment.checkpoints.map(c => (c.label, c.weights, c.allocation, c.estimate)) + (([*Both checkpoints*], "", "", [*#d.payment.combined*]),),
)
#if d.payment.estimates.len() > 0 [
  #note[#d.payment.estimates.len() recorded estimate(s); each is listed with its assumptions in the appendix.]
]

#v(4pt)
#note[Implementation rubric (0–3): #d.rubric.map(r => rating-badge(r.tone, r.score + " · " + r.label)).join(" ")]

// ── Goals ────────────────────────────────────────────────────────────────────
#section("Goals, targets and " + d.report.period + " progress")

#for g in d.goals [
  // The goal heading and notes stay on the same page as the start of its table.
  #block(sticky: true, width: 100%)[
    #text(size: 10pt, weight: "bold", g.title)
    #if g.description != "" [ \ #note(g.description)]
    \ #note(g.steps)
    #if g.review_note != "" [ \ #note(g.review_note)]
    #v(3pt)
  ]
  #block(breakable: true, width: 100%)[
    #data-table(
      columns: (2.3fr, 1.15fr, 1.3fr, 1.3fr),
      header: ("Metric", "Baseline & targets", "Actual · " + d.report.period, "Rating (0–3) · " + d.report.period),
      rows: g.metrics.map(m => (
        [*#m.code* #h(3pt) #note(m.category + if m.direction != "" { " · " + m.direction } else { "" } + if m.unit != "" { " · " + m.unit } else { "" }) \ #m.description#if m.source_note != "" [ \ #note(m.source_note)]],
        [Baseline #m.baseline \ 18-mo #m.target_18m \ 36-mo #m.target_36m],
        [#toned(m.status_tone, m.actual)#if m.status != "" [ \ #toned(m.status_tone, text(size: 7pt, m.status))]#if m.actual_source != "" [ \ #note(m.actual_source)]],
        [#rating-badge(m.rating_tone, m.rating) #if m.rating_source != "" [ \ #note(m.rating_source)]],
      )),
    )
    #v(6pt)
  ]
]
]

// ── Annual targets ───────────────────────────────────────────────────────────
#section("Annual state assessment targets")
#note[Percentage of tested students scoring Proficient or Advanced, including the alternate assessment. Compared only with the same school year, all grades, all students and the Combined assessment, by the same rule as the state results: “Meets target” when the whole published value is at or above the target, “Below target” when it is entirely below, “Range overlaps target” otherwise. A dashboard comparison, not an official rating.]
#v(3pt)
#if d.annual_year_mapping != "" [ #note(d.annual_year_mapping) #v(2pt) ]
#if d.annual.len() == 0 [ #note(d.scope.annual_empty) ] else {
  data-table(
    columns: (0.8fr, 0.55fr, 1.6fr, 0.55fr, 1.6fr),
    header: ("School year", "ELA goal", "ELA published (derived)", "Math goal", "Math published (derived)"),
    rows: d.annual.map(r => (r.year, s(r.ela_goal), toned(r.ela_tone, s(r.ela_published)), s(r.math_goal), toned(r.math_tone, s(r.math_published)))),
  )
}

// ── Other plan targets (shown as written, never compared) ────────────────────
#if d.plan_targets.len() > 0 [
  #section("Other plan targets")
  #note[Further targets from the continuous improvement plan (North Dakota - ND First Schools.pdf), shown exactly as written. None is compared with a result: each says why, and targets whose year or definition the source leaves open are marked unresolved.]
  #for t in d.plan_targets [
    #block(breakable: false, width: 100%, inset: (y: 4pt))[
      #text(weight: "bold", t.title) #h(4pt) #text(size: 7.5pt, fill: if t.status == "stated" or t.status == "confirmed" or t.status == "no_numeric_target" { c-muted } else { rgb("#9a6700") })[\[#t.status_label\]] \
      #t.measure
      #if t.baseline != "" [ \ #t.baseline]
      #if t.targets != "" [ \ #t.targets]
      #if t.long_term != "" [ \ #t.long_term]
      \ #note(t.status_note)
      \ #note[*#t.results_note*]
      \ #note(t.location)
    ]
  ]
]

// ── State results ────────────────────────────────────────────────────────────
#section("Official state results (ND Insights)")
#if not truthy(d.state.has_data) [
  #note[No official state results have been imported for this school.]
] else [
  // The filters, goal legend and Achievement heading travel together, so the
  // legend never sits alone at the bottom of a page.
  #let state-intro = block(sticky: true, width: 100%)[
    #note[#d.report.state_year · #d.report.state_type assessment · #d.report.state_subgroup. Annual results; not assigned to a seasonal period. #d.state.legend.intro]
    #if d.state.legend.reference != "" [#note[*#d.state.legend.reference*]]
    #v(2pt)
    #block(width: 100%, breakable: false)[
      #set text(size: 7pt)
      #for i in d.state.legend.items [#box[#swatch(i.tone) #h(2pt) #toned(i.tone, mark-symbol.at(i.tone, default: "–") + " " + i.label)] #h(8pt) ]
    ]
  ]

  // Each table starts on a page only with room for its heading, notes,
  // header and at least two rows; otherwise all of that moves to the next page.
  #let kept-table(head, rows, make) = {
    if rows.len() > 0 { keep-together(head + make(rows.slice(0, calc.min(2, rows.len())))) }
    head
    make(rows)
  }

  #let achievement-head = state-intro + lead([*Achievement*], d.state.notes.achievement + (if d.state.goal_years_note != "" { (d.state.goal_years_note,) } else { () }) + ("% tested shows the 95% participation target (ELA and math, Combined assessment, all students, All Grades) as a label; it is not a school goal.",))
  // achievement_empty is "" when achievement is published; otherwise the note
  // is printed and any rows with only % tested still follow in the table.
  #let achievement-head = if d.state.achievement_empty != "" { achievement-head + note(d.state.achievement_empty) } else { achievement-head }
  #if d.state.achievement.len() == 0 [ #achievement-head ] else {
    kept-table(achievement-head, d.state.achievement, rows => data-table(
      columns: (0.7fr, 0.65fr, 1.1fr, 0.9fr, 1.1fr, 0.7fr, 1fr, 0.85fr),
      header: ("Subject", "Grade", "Novice", "Approaching Proficiency", "Proficient", "Advanced", "Proficient or Advanced (derived)", "Tested"),
      rows: rows.map(r => (r.subject, r.grade, goal-cell(r.novice), goal-cell(r.partially), goal-cell(r.proficient), goal-cell(r.advanced), goal-cell(r.derived), goal-cell(r.tested))),
    ))
  }

  #let growth-head = lead([*Growth*], (if d.state.notes.growth.len() > 0 { (d.state.notes.growth.join(" "),) } else { () }) + ((d.state.notes.growth_matching + " The other growth measures have no matching goal.").trim(),))
  #if d.state.growth.len() == 0 [ #growth-head #note(d.state.growth_empty) ] else {
    kept-table(growth-head, d.state.growth, rows => data-table(
      columns: (0.55fr, 0.7fr, 0.75fr, 0.8fr, 0.7fr, 0.7fr, 0.85fr, 0.6fr, 1.45fr),
      header: ("Subject", "Grade", "Does not meet", "Approaches", "Meets", "Exceeds", "Meets or Exceeds (derived)", "Growth level", "Growth percentile"),
      rows: rows.map(r => (r.subject, r.grade, goal-cell(r.does_not_meet), goal-cell(r.approaches), goal-cell(r.meets), goal-cell(r.exceeds), goal-cell(r.derived), goal-cell(r.level), goal-cell(r.percentile))),
    ))
  }

  #let engagement-head = lead([*Student Engagement Survey* (all students)], (if d.state.notes.engagement.len() > 0 { (d.state.notes.engagement.join(" "),) } else { () }) + (if d.state.notes.engagement_matching != "" { (d.state.notes.engagement_matching,) } else { () }))
  #if d.state.engagement.len() == 0 [ #engagement-head #note(d.state.engagement_empty) ] else {
    kept-table(engagement-head, d.state.engagement, rows => data-table(
      columns: (1.2fr, 1fr, 1fr, 1fr),
      header: ("Engagement category", "Committed", "Compliant", "Disengaged"),
      rows: rows.map(r => (r.area, goal-cell(r.committed), goal-cell(r.compliant), goal-cell(r.disengaged))),
    ))
  }
  #note[Survey participation: #d.state.participation]
]

// ── Optional North Dakota comparison ─────────────────────────────────────────
#if truthy(d.nd_comparison.included) [
  #section("North Dakota comparison (optional)")
  // The intro and legend stay with the section heading.
  #block(sticky: true, breakable: false, width: 100%)[
    #note[#d.nd_comparison.legend.intro]
    #v(2pt)
    #set text(size: 7pt)
    #for i in d.nd_comparison.legend.items [#box[#swatch(i.tone) #h(2pt) #toned(i.tone, mark-symbol.at(i.tone) + " " + i.label)] #h(8pt) ]
  ]
  #v(2pt)
  #note[#d.nd_comparison.note]
  #for c in d.nd_comparison.coverage [ \ #note(c)]
  #if d.nd_comparison.engagement_benchmark != "" [ \ #note(d.nd_comparison.engagement_benchmark)]
  #if d.nd_comparison.rows.len() > 0 [
    #data-table(
      columns: (0.8fr, 0.75fr, 0.55fr, 0.95fr, 0.85fr, 0.85fr, 2.6fr),
      header: ("Section", "Subject", "Grade", "Measure", "This school", "North Dakota", "Comparison"),
      rows: d.nd_comparison.rows.map(r => (r.section, r.subject, r.grade, r.measure, cmp-cell((text: r.school, tone: r.tone, label: "")), r.state, [#toned(r.tone, mark-symbol.at(r.tone, default: "") + " " + r.label) \ #note(r.explanation)])),
    )
  ]
]

// ── Guidance ─────────────────────────────────────────────────────────────────
#section("How to read this report")
#notes-list(d.guidance)

// ── Appendix ─────────────────────────────────────────────────────────────────
// Follows on from the guidance (no forced page break), so the report doesn't
// end on a nearly empty page; the heading stays with the first section.
#v(14pt)
#block(sticky: true, below: 0pt, text(size: 14pt, weight: "bold")[Appendix: methodology and sources])

#section("Methodology")
#notes-list(d.appendix)

#if not building [
#section("Formal review estimates: calculation")
#block(breakable: false, width: 100%)[
  #note(d.payment.terms)
  #v(2pt)
  #data-table(
    columns: (1.1fr, 1fr, 1.3fr, 1fr, 1.6fr),
    header: ("Checkpoint", "Systems average (" + d.payment.systems_count + " metrics)", "Student Outcome average (" + d.payment.outcomes_count + " metrics)", "Weights", "Weighted score (of " + d.payment.max_rating + ")"),
    rows: d.payment.checkpoints.map(c => (c.label, c.systems_average, c.outcomes_average, c.weights, c.weighted)),
  )
  #note(d.payment.formula + " Allocations and estimates are in the “Estimated payment” table in the Summary.")
]
#if d.payment.estimates.len() > 0 [
  #v(2pt)
  #note[*Recorded estimates* (assumptions kept as recorded):]
  #notes-list(d.payment.estimates)
]
]

#section("Sources used in this report")
#notes-list(d.sources)

#section("Other imported ND Insights files")
#block(breakable: false, width: 100%)[
  #note(d.file_inventory_note)
  #if d.file_inventory.len() > 0 [
    #v(3pt)
    #notes-list(d.file_inventory)
  ]
]
