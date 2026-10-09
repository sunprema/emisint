# Plan: CRD Dashboard tab (Authorizer Portfolio)

## Approach

Add a fourth tab, **CRD Dashboard**, to `/authorizer-portfolio`
(`lib/emisint_web/live/dashboard/portfolio_live.ex`), sitting next to the
existing **M-STEP Dashboard** and **SAT Dashboard** tabs. It shows the
**CRD Delta** for every school in the selected chartering agency's portfolio:

> CRD Delta = charter's all-subjects M-STEP proficiency
>           − enrollment-weighted Composite Resident District (CRD) average

This is the same number the district detail page already shows as
"-13.7 pts vs CRD Composite" (Central Academy, 81902) in
`EmisintWeb.Mde.DistrictAnalysisLive`. The dashboard must reproduce that
value exactly, so the math is lifted into a shared module rather than
re-implemented.

**Layout** mirrors `portfolio_dashboard/1` (the M-STEP tab) so the three
dashboards feel like one system:

- Header with title and the shared year selector (`select_stats_year`).
- Three summary cards: **Exceeds CRD**, **Below CRD**, **No CRD Data**.
- Stacked green/red proportion bar.
- Per-school diverging bar chart sorted best to worst, with a `±N.N pp`
  badge, each row linking to the school's CRD comparison detail page.
- Exclusions table listing schools with no delta and *why* (no CRD rows,
  charter has no district snapshot for the year, no resident district has a
  snapshot).

**Granularity.** CRD data is keyed by *charter district code*, not building.
The M-STEP tab is per building; the CRD tab will be per charter district
(`MdeEntityMaster.district_code`). For agency 5017 the 72 buildings collapse
to 57 charter districts, 55 of which have CRD rows and 47 of which have a
district snapshot. Rows will be labelled with the district snapshot name.

**Data loading** is batched to avoid the N×M query fan-out the detail page
does per district (it is fine there, it is not fine for 57 schools):

1. One Ash read of `MdeCompositeResidentDistrict` for all charter codes in
   the portfolio, loading `mde_district` for the resolved resident code.
2. One Ash read of `MdeDistrictSnapshot` for the year covering the charter
   codes plus every distinct resident district code, selecting only
   `district_code`, `district_name`, `all_subjects`.
3. Compute composites and deltas in memory with the shared module.

**Shared module.** New `Emisint.Assessments.CrdComparison` holds the pure
math (`weighted_subject/2`, `avg_of_subjects/1`, composite, delta) and the
batched portfolio loader. Follows the `EmoPortfolio` precedent of pulling
shared logic out of a LiveView so the LiveView, detail page, and PDFs cannot
drift apart. Refactoring the detail page and the CRD PDF onto it is listed as
separate, optional tasks so the dashboard can ship without touching them.

## Tasks

### Core (needed for the tab to work)

- [x] Create `lib/emisint/assessments/crd_comparison.ex` — pure functions
      `subjects/0`, `weighted_subject/2`, `avg_of_subjects/1`,
      `composite_subjects/1`, `delta/2`, reproducing the detail page's
      two-step one-decimal rounding exactly
- [x] Add `CrdComparison.portfolio_deltas(charter_codes, year)` — batched
      loader (2 reads) returning one row per charter district:
      `%{district_code, district_name, charter_avg, composite_avg, delta,
      resident_count, scored_count, total_students, excluded?, exclusion_reason}`
      sorted best to worst with exclusions last
- [x] `portfolio_live.ex`: add `:crd_dashboard` tab button between M-STEP and
      SAT (icon `hero-arrows-right-left` or similar), and the tab content block
- [x] `portfolio_live.ex`: assign `crd_portfolio_stats` in `mount`,
      both `handle_params` clauses, and `select_stats_year`; derive charter
      codes from `schools` via `district_code` (uniq, reject nil)
- [x] `portfolio_live.ex`: add `crd_dashboard/1` component modelled on
      `portfolio_dashboard/1` — header, 3 cards, proportion bar, per-school
      diverging bars, exclusions table with reason column, empty state
- [x] Each per-school row links to
      `~p"/mde/districts/#{code}?tab=crd_comparison"` for drill-down
- [x] `mix format`, compile with no warnings, and manually confirm Central
      Academy (81902) shows -13.7 on the dashboard for 24-25

### Consistency refactors (optional, recommended)

- [ ] Refactor `DistrictAnalysisLive.load_crd_comparison/2` and
      `crd_scope_summary/2` to call `CrdComparison` helpers — no behaviour
      change, detail page values must be identical before and after
- [ ] Refactor `Emisint.Reports.School.CrdComparisonPdf` (`scope_summary/1`,
      `weighted/2`, `avg_floats/1`) onto `CrdComparison`

### Enhancements (optional)

- [ ] Add an **All / Top 10** resident-district scope toggle to the CRD
      Dashboard, matching the detail page's `select_crd_scope`
- [x] Add a **CRD** section to the authorizer portfolio PDF
      (`lib/emisint/reports/portfolio/portfolio_pdf.ex` + Typst template) so
      "Download PDF" includes the new tab's data

### Tests

- [ ] `test/emisint/assessments/crd_comparison_test.exs` — unit tests for
      weighting, nil-subject handling, rounding, and `portfolio_deltas/2`
      against seeded `MdeCompositeResidentDistrict` + `MdeDistrictSnapshot`
      rows (including a charter with no CRD rows and one whose residents
      have no snapshots)
- [ ] LiveView test: switching to the CRD tab renders the summary cards and a
      row for a seeded school with the expected delta badge

## Notes & Risks

- **CRD year vs. assessment year.** CRD rows carry `school_year = "2025-26"`
  while assessment snapshots use `"24 - 25 School Year"`. The detail page
  does *not* filter CRD rows by year; it treats the enrollment weights as
  static and only the snapshot is year-specific. The dashboard will do the
  same for parity. If a second CRD year is ever imported, both pages will
  double-weight districts unless a year mapping is added. Flagging now.
- **Asymmetric averaging is intentional.** Charter side is an unweighted mean
  of four subjects; composite side is a mean of four enrollment-weighted
  subject means. Keeping it so the dashboard matches the detail page.
- **Nil subjects shift the average.** `avg_of_subjects` drops missing
  subjects, so a charter with three scored subjects is compared against a
  composite that may have four. Same as today; not changing in this plan.
- **Building vs. district.** Multiple buildings under one charter district
  show as a single row. The M-STEP tab's per-building count will not match the
  CRD tab's row count; the cards should say "districts" or "schools" clearly.
- **`switch_tab` uses `String.to_existing_atom/1`.** `:crd_dashboard` is
  referenced in the template, so the atom exists at compile time. No change
  needed, but worth knowing if the tab name changes.
- **Resident district resolution** must use `mde_district_id` → `MdeDistrict
  .district_code`, never `crd_district_code` (known unreliable, see memory).
- **Default `authorize?: false`** matches every other MDE read in this
  LiveView; MDE public data is not tenant-scoped.
- Task order: the shared module comes first; the LiveView tasks depend on it.
  The refactors and enhancements are independent of each other.

## Verification Plan

1. `mix test test/emisint/assessments/crd_comparison_test.exs`
2. Start the server, open `/authorizer-portfolio?agency=5017`, switch to
   **CRD Dashboard**, confirm card counts sum to 57 and Central Academy reads
   -13.7 pp for 24-25.
3. Change year to 22-23 and confirm the tab reloads without error.
4. Click a school row and confirm it lands on the CRD comparison tab of the
   detail page with the same delta.
5. If the refactor tasks run: diff detail page values for two or three
   districts before and after.
