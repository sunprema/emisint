# Plan: ED% vs Performance Regression Charts (ESP Portfolio)

## Approach

Add a "Regression" tab to `/esp-portfolio` with two scatter charts for the
selected management organization's school portfolio (starting with CS
Partners): **M-STEP vs Economically Disadvantaged %** and **SAT vs
Economically Disadvantaged %**. Each dot is one school. Both charts get a
linear regression trend line and a 4-quadrant background split at the
Michigan statewide averages, colored per the "beating the odds" scheme you
picked:

- High ED + high performance → **green** (outperforming expectations)
- Low ED + low performance → **red** (underperforming despite advantage)
- The other two quadrants ("as expected" either way) → **yellow**

Both Y-axis values already exist from data/infra built in the last feature —
no new ingestion needed:
- M-STEP Y-value: `mde_school_vs_lea_snapshots.all_subjects_avg->>'school_pct'`
  (already the K-8 all-subjects composite proficiency per building — M-STEP is
  inherently a grades 3-8 test, so no extra grade filtering is needed).
  Statewide threshold reuses the same row's `state_pct`.
- SAT Y-value: `mde_sat_results` where `rollup_level == :building`,
  `subgroup == "All Students"`, `all_subject_score_average` (SAT has no grade
  field at all — it's inherently 11th-grade/9-12 reporting). Statewide
  threshold: the `isd_code == "0"` ("Statewide") row, same table/subgroup.
- The one new piece: **ED%** (X-axis, both charts) from
  `MdeEnrollmentResult.economic_disadvantaged_enrollment / total_enrollment`,
  `rollup_level == :building`. Statewide threshold: the `isd_code == "0"` row
  of the same table (confirmed present: ~50.3% for 24-25).

The school population for the chart is `EmoPortfolio.resolve_schools/1` —
the same override-aware list from the feature we just shipped — so a school
manually added/removed from CS Partners' portfolio is reflected here too.

Charts are hand-built inline SVG (no new JS charting dependency — matches
this codebase's existing pattern of plain HTML/CSS/SVG visualizations, e.g.
`portfolio_dashboard`'s bar rows). Colors reuse the app's existing DaisyUI
`success`/`warning`/`error` tokens (already used for Exceeds/Below LEA
elsewhere) rather than introducing a separate palette.

**Phase 2 (explicitly deferred, per your note):** historical/multi-year trend
view. This phase is single selected-year only, matching the existing
`@stats_year` selector already on the page.

## Tasks

- [ ] Add `Emisint.Assessments.EdRegression` module:
  - `mstep_points(management_organization, year)` — one point per resolved
    school: `%{school_name, building_code, ed_pct, value}`
  - `sat_points(management_organization, year)` — same shape, SAT value
  - `state_ed_pct(year)`, `state_mstep_pct(year)`, `state_sat_score(year)` —
    statewide thresholds for the quadrant crosshair
  - Least-squares linear regression helper (slope/intercept) over each
    point set, for the trend line
  - Quadrant/color classifier per school (green/yellow/red) against the
    statewide thresholds
  - Exclude schools missing ED% or a performance value from the plotted
    set; surface them in a small "excluded — missing data" list (same
    pattern as the existing "no LEA match" lists)
- [ ] Add a "Regression" tab to `esp_portfolio_live.ex` (alongside Schools /
      M-STEP Dashboard / SAT Dashboard), reusing `@stats_year` and
      `@schools`/`@selected_emo`
- [ ] Build the scatter chart as an inline-SVG function component (shared
      by both charts, parameterized by axis labels/domain): quadrant
      background fill, regression line, ≥8px dot markers colored by
      quadrant, hover tooltip per dot (school name + both values), small
      legend for the 3 colors, recessive gridlines, no dual axes
  - Run `scripts/validate_palette.js` (dataviz skill) against the DaisyUI
    success/warning/error hex values actually rendered, in both light and
    dark mode, before calling the color scheme done
- [ ] Handle the <3-schools-with-data edge case: show a note instead of a
      misleading regression line (a line through 1-2 points is meaningless)
- [ ] Manual test against CS Partners: spot-check a couple of schools'
      plotted ED%/M-STEP/SAT values against direct DB queries, confirm
      quadrant colors and regression line look sane, check both light and
      dark theme

## Notes / risks

- **M-STEP statewide threshold**: reusing the snapshot's cached
  `state_pct` (already computed by `MdeComparisonSnapshotWorker`) rather
  than re-querying `MdeStateAssessmentResult` isd_code "0" directly — it's
  the same number and avoids a second computation path, but flag if you'd
  rather it query fresh.
- **Authorizer Portfolio parity**: you said "each authorizer or management
  company will see their portfolio" — this phase only touches ESP
  Portfolio (`esp_portfolio_live.ex`), since that's what CS Partners is.
  Bringing the same tab to the Authorizer Portfolio page
  (`portfolio_live.ex`, chartering-agency-based) is a natural follow-up,
  not included here unless you want it now.
- **Small portfolios**: CS Partners-sized (~10-12 schools) portfolios give
  a fairly noisy regression line — that's inherent to the data, not a bug,
  but worth expecting when you look at it.
