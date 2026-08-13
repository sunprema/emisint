// Customizable detailed landscape school report.
#import "/shared/design_system.typ": *
#import "/school/custom_report_sections.typ": custom-report-sections

#set page(
  paper: "us-letter",
  flipped: true,
  margin: (top: 0.5in, bottom: 0.6in, left: 0.6in, right: 0.6in),
  header: context {
    set text(font: "Helvetica Neue", size: 7.5pt, fill: c-muted)
    grid(columns: (1fr, auto), [Emisint Custom School Performance Report], [#elixir_data.report_year_label])
    line(length: 100%, stroke: 0.5pt + c-border)
  },
  footer: context {
    set text(font: "Helvetica Neue", size: 7.5pt, fill: c-muted)
    grid(columns: (1fr, auto), [Confidential — Emisint], [Page #counter(page).display()])
  }
)
#set text(font: "Helvetica Neue", size: 9pt, fill: c-text)

#grid(
  columns: (auto, 1fr, auto),
  gutter: 14pt,
  align: horizon,
  image("/school/emisint_small_logo.png", width: 40pt),
  {
    text(size: 20pt, weight: "bold", fill: c-primary, disp-str(elixir_data.school.name))
    linebreak()
    text(size: 9pt, fill: c-muted, elixir_data.report_year_label + " Detailed Custom Report")
  },
  align(right, {
    text(size: 9pt, weight: "semibold", disp-str(elixir_data.org_name))
    linebreak()
    text(size: 8pt, fill: c-muted, "Generated " + elixir_data.generated_on)
  })
)
#v(6pt)
#line(length: 100%, stroke: 1pt + c-primary)

#custom-report-sections(elixir_data, elixir_data.sections)
