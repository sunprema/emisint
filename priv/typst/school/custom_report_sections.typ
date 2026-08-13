#import "/shared/design_system.typ": *

#let enabled(value) = if type(value) == str { value == "true" } else { value == true }
#let missing(value) = value == none or value == "" or value == "nil" or value == "—"

#let unavailable(message) = rect(
  width: 100%,
  inset: 12pt,
  radius: 4pt,
  fill: c-row-alt,
  stroke: 0.5pt + c-border,
  text(size: 8.5pt, fill: c-muted, style: "italic", message)
)

#let custom-report-sections(data, sections) = {
  if enabled(sections.school_profile) {
    section-title("School Profile")
    grid(
      columns: (1fr, 1fr),
      gutter: 20pt,
      {
        detail-row("Address", disp-str(data.school.street) + ", " + disp-str(data.school.city) + ", " + disp-str(data.school.state) + " " + disp-str(data.school.zip))
        detail-row("Grades Served", data.school.grades_served)
        detail-row("Contract Grades", data.school.contract_grades)
      },
      {
        detail-row("Year Opened", data.school.year_opened)
        detail-row("Intermediate District", data.school.isd_name)
        detail-row("Authorizer", data.org_name)
      }
    )
  }

  if enabled(sections.mission_statement) {
    section-title("School Mission")
    if missing(data.school.mission) {
      unavailable("Mission statement data is not available from a verified source.")
    } else {
      text(data.school.mission)
    }
  }

  if enabled(sections.charter_contract) {
    section-title("Charter Contract and Educational Service Provider")
    if missing(data.contract.term_length) and missing(data.contract.expiration_year) and missing(data.contract.esp_name) {
      unavailable("Contract term, expiration, and educational service provider data are not available from a verified source.")
    } else {
      grid(
        columns: (1fr, 1fr, 1fr),
        gutter: 12pt,
        stat-box("Contract Term", disp-str(data.contract.term_length)),
        stat-box("Expiration Year", disp-str(data.contract.expiration_year)),
        stat-box("Educational Service Provider", disp-str(data.contract.esp_name))
      )
    }
  }

  if enabled(sections.board_roster) {
    section-title("Board Roster")
    if data.board_members.len() == 0 {
      unavailable("Board member and term data are not available from a verified source.")
    } else {
      table(
        columns: (2fr, 1.4fr, 1fr, 1fr),
        stroke: 0.4pt + c-border,
        inset: (x: 8pt, y: 6pt),
        table.header(th("Name"), th("Role"), th("Appointed"), th("Term Ends")),
        ..data.board_members.map(member => (
          disp-str(member.name),
          disp-str(member.role),
          disp-str(member.appointed),
          disp-str(member.term_ends),
        )).flatten()
      )
    }
  }

  if enabled(sections.performance_overview) {
    section-title("School Performance Overview")
    let overview = data.performance_overview
    grid(
      columns: (1fr, auto),
      row-gutter: 8pt,
      text(weight: "semibold", "Academic Achievement"),
      status-pill(overview.academic_achievement),
      text(weight: "semibold", "Academic Growth"),
      status-pill(overview.academic_growth),
      text(weight: "semibold", "Compliance Reporting Condition"),
      text(fill: c-muted, style: "italic", "Data unavailable"),
      text(weight: "semibold", "Financial Reporting Condition"),
      text(fill: c-muted, style: "italic", "Data unavailable")
    )
  }

  if enabled(sections.enrollment_demographics) {
    section-title("Enrollment and Demographics")
    grid(
      columns: (0.7fr, 1.3fr),
      gutter: 20pt,
      stat-box("Total Enrollment", fmt-int(data.enrollment.total)),
      {
        text(weight: "semibold", size: 9pt, "Current Demographic Subgroups")
        v(6pt)
        horizontal-bars(data.enrollment.subgroups, color: c-primary)
      }
    )
    v(8pt)
    unavailable("Five-year enrollment trend and multi-year enrollment-by-grade data are not yet available.")
  }

  if enabled(sections.resident_districts) {
    section-title("Student Resident Districts")
    let colors = (c-primary, c-accent, c-warning, c-border.darken(10%))
    let slices = data.resident_districts.enumerate().map(((index, district)) => (
      name: district.name,
      pct: district.pct,
      color: colors.at(calc.rem(index, colors.len())),
    ))
    if slices.len() == 0 {
      unavailable("Resident-district data are unavailable for this school and year.")
    } else {
      grid(
        columns: (auto, 1fr),
        gutter: 24pt,
        align: horizon,
        pie-chart(slices, radius: 44pt),
        pie-legend(slices)
      )
    }
  }

  if enabled(sections.sss_peer_roster) {
    section-title("Roster of Statistically Similar Schools")
    if data.peer_roster.len() == 0 {
      unavailable("The SSS peer roster has not yet been normalized for customizable reports. No sample peers or distances are shown.")
    } else {
      table(
        columns: (1fr, 3fr),
        stroke: 0.4pt + c-border,
        inset: (x: 8pt, y: 6pt),
        table.header(th("Distance in Miles"), th("Peer School Name")),
        ..data.peer_roster.map(peer => (fmt1(peer.distance), disp-str(peer.name))).flatten()
      )
    }
  }

  if enabled(sections.accountability) {
    section-title("Accountability Indicators")
    grid(
      columns: (1fr, 1fr),
      gutter: 24pt,
      align(center, {
        text(weight: "bold", "School Index")
        v(8pt)
        gauge(data.school_index.value, 100.0, c-accent, size: 105pt)
      }),
      align(center, {
        text(weight: "bold", "Assessment Participation")
        v(8pt)
        gauge(data.participation.value, 100.0, c-success, size: 105pt)
        v(4pt)
        text(size: 8pt, fill: c-muted, "Federal minimum: 95.0%")
      })
    )
    v(6pt)
    align(center, text(size: 8.5pt, "MDE Support Category: " + disp-str(data.participation.support_category)))
  }

  if enabled(sections.academic_trends) {
    section-title("Charter Contract Academic Performance Trends")
    unavailable("Multi-year peer-relative achievement and growth trend data are not available.")
    v(8pt)
    grid(
      columns: (1fr, 1fr),
      gutter: 12pt,
      stat-box("Current ELA Mean SGP", fmt1(data.sgp.ela)),
      stat-box("Current Math Mean SGP", fmt1(data.sgp.math))
    )
  }

  if enabled(sections.proficiency_trends) {
    section-title("M-STEP Proficiency Trends by Subject")
    unavailable("Multi-year school, state, and peer proficiency trend data are not available.")
    v(8pt)
    table(
      columns: (1.4fr, 1fr, 1fr),
      stroke: 0.4pt + c-border,
      inset: (x: 8pt, y: 6pt),
      table.header(th("Current Year"), th("School"), th("State")),
      "ELA", pct-badge(data.proficiency.school_ela), pct-badge(data.proficiency.state_ela),
      "Mathematics", pct-badge(data.proficiency.school_math), pct-badge(data.proficiency.state_math)
    )
  }

  if enabled(sections.academic_compliance_appendix) {
    pagebreak(weak: true)
    section-title("Academic and Compliance Appendix")
    text(weight: "bold", fill: c-primary, "Academic Achievement")
    v(3pt)
    text(size: 8.5pt, "Academic Achievement reflects state-assessment proficiency relative to state and peer benchmarks.")
    v(8pt)
    text(weight: "bold", fill: c-primary, "Academic Growth")
    v(3pt)
    text(size: 8.5pt, "Academic Growth uses Student Growth Percentile (1–99), where 50 represents typical statewide growth.")
    v(8pt)
    text(weight: "bold", fill: c-primary, "Compliance Reporting Conditions")
    v(3pt)
    text(size: 8.5pt, "Exceeds: complete and timely reporting. Meets: minor corrected issues. Does Not Meet: missing, late, or materially inaccurate reports.")
  }

  if enabled(sections.financial_testing_appendix) {
    section-title("Financial and Testing Appendix")
    text(weight: "bold", fill: c-primary, "Financial Conditions")
    v(3pt)
    text(size: 8.5pt, "Exceeds: strong reserves and no material findings. Meets: stable position. Does Not Meet: indicators of financial distress.")
    v(8pt)
    table(
      columns: (1.2fr, 1.4fr, 2fr),
      stroke: 0.4pt + c-border,
      inset: (x: 8pt, y: 6pt),
      table.header(th("Subject"), th("Grades"), th("Michigan Test(s)")),
      "ELA", "3–8, 11", "M-STEP (3–8), PSAT (8, 10), SAT (11)",
      "Math", "3–8, 11", "M-STEP (3–8), PSAT (8, 10), SAT (11)",
      "Social Studies", "5, 8, 11", "M-STEP",
      "Science", "5, 8, 11", "M-STEP"
    )
  }
}
