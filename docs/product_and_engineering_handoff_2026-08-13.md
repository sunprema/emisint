# Emisint Product and Engineering Handoff

**Prepared:** August 13, 2026
**Current branch:** `betterPDF`
**Primary contributor identity:** `bryce@odti.net` (commits authored as both `Dmitry` and `brycesamoylov`)

## Executive Summary

My work on Emisint focused on turning Michigan education data into practical comparisons, portfolio analysis, and client-ready PDF reporting. The largest additions were:

- Statistically Similar Schools (SSS) import, comparison, and reporting.
- Student Growth Percentile (SGP) import, comparison, visualization, and filtering.
- Better ESP portfolio management and economically disadvantaged (ED%) regression analysis.
- A shared PDF design system and reusable report-generation foundation.
- New Performance Report, Board Summary, and standalone regression report formats.

The existing feature work through July 24 is on `origin/dev`. The PDF report foundation has been committed locally on `betterPDF` as `56b8ea4`, but has not yet been pushed. A template-picker implementation is also present in the working tree as unfinished, uncommitted work and must be reviewed before it is committed.

## Product Capabilities Added

### Statistically Similar Schools

- Added resources for SSS schools, comparison groups, and group membership.
- Added CSV/TSV importing and an Oban background worker.
- Added system-administrator upload controls and import tracking.
- Added an SSS comparison experience in District Analysis.
- Added a Typst PDF comparison report.

### Student Growth Percentile

- Added building- and district-level SGP storage and import processing.
- Added an SGP upload workflow and background worker.
- Added School vs. LEA, District Comparison, and Composite Resident District comparisons.
- Added subject filtering, grade/subject tables, and Mean SGP charts.
- Reorganized long District Analysis pages into durable LiveView-driven collapsible sections.

### ESP Portfolio Management and Regression

- Added manual school add/remove overrides for management-organization portfolios.
- Centralized school resolution so the dashboard and PDF use the same portfolio membership.
- Added ED% versus M-STEP and SAT regression analysis.
- Added quadrant analysis, least-squares trend lines, dashboard charts, and PDF output.

### PDF and Report Foundation

- Created a shared Typst design system with consistent colors, typography, badges, tables, charts, number coercion, and unavailable-value handling.
- Migrated the principal report templates to the shared components.
- Added real Emisint branding and release-safe template root paths.
- Added a detailed School Performance Report.
- Added a real-data-only, one-page Board Summary.
- Added a standalone ESP regression report.
- Extracted `SchoolSnapshot` so school identity, enrollment, resident districts, School Index, SGP, and proficiency data are loaded consistently.
- Added smoke tests for all current PDF generators. The last verified report-only baseline was 16 passing tests.
- Removed unreachable regression code from the portfolio template after finding that its data was never populated.

## Commit History

| Date | Commit | Change | Remote status |
|---|---|---|---|
| 2026-07-14 | `d0f68d3` | Added SSS import, resources, UI, comparison workflow, and PDF report | On `origin/dev` |
| 2026-07-17 | `684a357` | Added MDE SGP import, storage, upload workflow, and display | On `origin/dev` |
| 2026-07-17 | `2b2f7a3` | Added SGP comparison to the Composite Resident District tab | On `origin/dev` |
| 2026-07-17 | `1d79cf3` | Added manual ESP portfolio school overrides and shared portfolio resolution | On `origin/dev` |
| 2026-07-17 | `ea56d55` | Added ED% versus performance regression charts and PDF output | On `origin/dev` |
| 2026-07-22 | `c418f69` | Added collapsible MDE sections, consistent ordering, and SGP charts | On `origin/dev` |
| 2026-07-24 | `757ef6a` | Integrated the SGP/collapsible-section work into the development line | On `origin/dev` |
| 2026-07-24 | `dbf08a0` | Integrated the SSS feature and resolved cross-feature conflicts | On `origin/dev` |
| 2026-08-13 | `56b8ea4` | Added the shared PDF report foundation, reports, templates, and smoke tests | Local `betterPDF`; not pushed |

## Current Repository State

- `betterPDF` currently points to local commit `56b8ea4`.
- `56b8ea4` is the clean baseline for the completed PDF foundation and should be pushed with the branch after review.
- The working tree contains a simple, functional visual-template picker: a code-owned registry, normalized real-data payload, compact and detailed layouts, authenticated builder/PDF routes, and focused tests.
- Template selection applies to one generated report. Compact portrait is the default; no organization preference is persisted.
- No report-configuration resource or database migration is required. Persisted organization defaults remain a future product decision.
- Users can include or omit the full Performance Report catalog for each generated report:
  - School profile.
  - Mission statement.
  - Charter contract and educational service provider.
  - Board roster.
  - Performance overview.
  - Enrollment and demographics.
  - Resident districts.
  - Statistically similar schools.
  - Accountability indicators.
  - Achievement and growth trends.
  - Proficiency trends.
  - Academic and compliance appendix.
  - Financial and testing appendix.
- Sections without verified backing data remain selectable but render “Data unavailable”; legacy sample values are never copied into customizable output.
- `pitch_deck_MSU.md` is unrelated to the PDF implementation and should not be included automatically in a code commit.
- `setup_bryce` is local operational documentation and must not be committed. It contains environment-specific startup details.

## What’s Next

### 1. Finish PDF Template Creation and the Template Picker

This is the immediate next milestone for `betterPDF`.

- Review the current uncommitted picker implementation file by file.
- Finalize two visual presets that render the same normalized, real-data-only school report payload:
  - `compact_portrait`
  - `detailed_landscape`
- Ensure missing values render as “Data unavailable”; do not use sample values in selectable reports.
- Keep template selection stateless until the team decides whether organization-wide defaults are needed.
- Verify the authenticated report-builder LiveView and secure PDF generation route in a representative development account.
- Keep existing fixed report URLs during rollout.
- Render both PDFs to images and visually inspect every page for clipping, spacing, pagination, and chart/table readability.
- Re-run the report and picker tests before committing. Resolve or explicitly document the repository's existing warnings-as-errors precommit baseline.
- Commit the picker separately from `56b8ea4`, push `betterPDF`, and open a pull request into `dev`.

### 2. Replace Remaining Sample Report Data

The detailed legacy Performance Report still contains clearly isolated sample data because backing resources do not exist. Add real sources for:

- Board members and terms.
- Charter contract term and expiration.
- Compliance and financial reporting ratings.
- School mission statement.
- Attendance.
- Multi-year enrollment, achievement, growth, and proficiency history.

SSS distance-in-miles is not available in the current MDE source and should remain an explicit limitation unless another verified source is introduced.

### 3. Complete Report Rollout and Cleanup

- Perform visual QA across supported templates and representative schools.
- Add administrator documentation for choosing and generating reports.
- Monitor report generation errors and unavailable-data frequency.
- Retire duplicate fixed reports only after the picker can reproduce their real-data content reliably.
- Extend the same template system to ESP and authorizer portfolio reports after the school-report workflow is stable.

### 4. Stabilize the Broader Test Baseline

- Keep report tests isolated and green.
- Review older failing tests that reference resources removed during `resource_cleanup`.
- Remove obsolete tests or restore intended coverage so `mix precommit` becomes a trustworthy signal for future contributors.

## Operational Notes

- The application runs inside WSL Ubuntu; Elixir, Erlang, PostgreSQL, and asdf are installed there rather than in Windows.
- PostgreSQL uses port `5433`.
- The Phoenix application is served at `http://localhost:4000`.
- Use `setup_bryce` locally for the exact environment startup procedure, but sanitize its useful operational guidance before placing anything in shared documentation.
- Do not run unscoped `mix format`; pass only the files intentionally changed.
- Preserve unrelated working-tree changes and inspect `git status` before staging.
