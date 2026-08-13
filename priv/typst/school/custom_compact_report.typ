// Customizable compact portrait school report.
#import "/shared/design_system.typ": *
#import "/school/custom_report_sections.typ": custom-report-sections

#set page(
  paper: "us-letter",
  margin: (top: 0.65in, bottom: 0.65in, left: 0.65in, right: 0.65in),
  footer: context {
    set text(size: 7.5pt, fill: c-muted, font: "Helvetica Neue")
    line(length: 100%, stroke: 0.5pt + c-border)
    grid(columns: (1fr, auto), [Confidential — Emisint], [Page #counter(page).display()])
  }
)
#set text(font: "Helvetica Neue", size: 9pt, fill: c-text)

#grid(
  columns: (auto, 1fr, auto),
  gutter: 12pt,
  align: horizon,
  image("/school/emisint_small_logo.png", width: 34pt),
  {
    text(weight: "bold", size: 16pt, fill: c-primary, disp-str(elixir_data.school.name))
    linebreak()
    text(size: 8.5pt, fill: c-muted, elixir_data.report_year_label + " Custom School Report")
  },
  align(right, text(size: 8pt, fill: c-muted, disp-str(elixir_data.org_name)))
)
#v(4pt)
#line(length: 100%, stroke: 1pt + c-primary)

#custom-report-sections(elixir_data, elixir_data.sections)
