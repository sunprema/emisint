# Plan: PDF Report Generation (branch `betterPDF`)

## Resume prompt (paste this into a new chat)

```
Read PLAN_betterPDF.md, CLAUDE.md, and .claude/skills/typst/SKILL.md.
If setup_bryce exists at the repo root, read it too — it has exact
steps for this dev environment (WSL/asdf/Postgres port quirks, how to
start the server, how to run tests) that aren't written down anywhere
else. Look at "Where we are now" at the top of PLAN_betterPDF.md and
the Phase checklists below it to see what's already shipped and what
the next unfinished milestone is. Check test/emisint/reports/ for the
existing smoke-test pattern before adding to it. Determine the next
unfinished milestone. Create a detailed implementation plan before
writing any code. Present the plan for review. After approval,
implement the milestone incrementally, ensuring all tests pass,
documentation is updated (including this file), and no architecture
decisions violate the project principles.
```

## Vision (end goal)

Emisint's PDF reports should become **customizable**: a client (EMO/ESP admin
or Authorizer) picks *what* goes in a report (which sections — enrollment,
M-STEP, SGP, School Index, board info, peer comparison, regression, etc.)
and *which visual format/template* to render them in, and the system
composes a tailored PDF from a shared library of report sections instead of
each report being its own bespoke, hand-built Typst file.

Getting there requires, roughly in order:

1. A **shared component/design-system library** in Typst (color tokens,
   typography, page chrome, reusable section blocks) — without this, every
   new "template" is more copy-paste debt, not progress toward a picker.
2. A handful of **distinct, polished template presets** built *from* that
   shared library, so there's a real menu to choose from and a proven
   pattern of composing shared sections before building the picker itself.
3. **Real data behind every section** that could plausibly ship to a client
   — right now several sections are placeholder/sample data because no
   backing resource exists yet (see "Data completeness" below).
4. The actual **customization engine**: a config of which sections + which
   template a client wants, a backend that composes the PDF from that
   config, and a UI to set/save the choice per client.
5. **Tests, visual QA, and cleanup** of the older ad hoc reports once the
   shared library exists, so the whole system — old and new — is on one
   consistent foundation.

This file tracks that path. The "Tasks" section below is organized as
phases toward that vision, not a flat backlog.

## Where we are now (as of 2026-07-30)

**Status: Phase 0 and Phase 1 are both fully worked through.** Phase 0
(shared design-system partial, coercion/chart consolidation, real logos,
smoke tests) is 100% done. Phase 1 (expand the template library) is done
to the extent it can be right now: 1.1 shipped (Board Summary, the second
visual preset), 1.3 shipped (full section-library catalog, below), and 1.2
(`comprehensive.typ`'s fate) is *deliberately* left unchecked — re-confirmed
deferred rather than decided, so it stays open on purpose until there's an
actual reason to revisit it. **Nothing on this branch has been committed
yet** — every session's work, going back to Phase 0, is still sitting as
uncommitted changes in the working tree (confirmed via `git status`).

**Next unfinished milestone**: either **Phase 2** (close real data gaps —
Board Member data, Charter Contract terms, Compliance/Financial ratings,
mission statement, multi-year history, SSS distance-in-miles) or **Phase
3** (build the actual customization engine — config schema, backend
composition, picker UI, persistence). Phase 3 is more valuable long-term
but Phase 2 is what turns today's "REAL vs. SAMPLE" caveats into reports a
client could actually be shown as complete. Needs a decision on which to
start before the next session picks a task.

### Shipped 2026-07-30 — Phase 1.3 (section library catalog) + cleanup

- **Cataloged every distinct section across all 7 in-scope templates**
  (plus `comprehensive.typ` separately) as the literal menu Phase 3's
  picker will offer — see "Section Library Catalog" below. 1.2
  (`comprehensive.typ`'s fate) re-confirmed deferred, same call as 0.5.
- **Found and fixed a real bug while cataloging**: `portfolio.typ` had a
  full ED%-vs-performance regression section (scatter charts + excluded-
  count text), but `PortfolioPdf.build_data/2` never populated the
  `elixir_data.regression` key the template's `#if regression != none`
  checked — so the section was unreachable dead code, silently never
  rendering. The real, working version of this regression already exists
  standalone in `RegressionPdf`/`regression_report.typ` (ESP-Portfolio-
  scoped by product decision). Removed the dead section and its
  `scatter-chart` helper from `portfolio.typ` rather than wiring it up,
  per your call — avoids duplicating what `RegressionPdf` already does.
  `test/emisint/reports/` (16/16) still passes.

### Shipped 2026-07-30 — Phase 1.1 (second visual preset: Board Summary)

Proves Phase 0's "compose from shared parts" pattern repeats, per 1.1's
brief:

- **New one-page, US-Letter-portrait "Board Summary" report** —
  `lib/emisint/reports/school/board_summary_pdf.ex` +
  `priv/typst/school/board_summary.typ`, wired to
  `GET /mde/board-summary.pdf` via a new
  `EmisintWeb.MdeBoardSummaryReportController`, with a "Board Summary"
  button added next to "Full Performance Report" on the School vs LEA tab.
  Deliberately a different layout philosophy than the Performance Report
  (single page, portrait, no pagebreaks) built entirely from
  `design_system.typ` components (`gauge`, `stat-box`, `status-pill`,
  `pct-badge`, `sgp-badge`, `pie-chart`/`pie-legend`, `section-title`) —
  no new chart primitives needed, which is the actual proof point for 1.1.
- **Deliberately REAL-data-only** (a scoped decision, not an oversight):
  School Index, Assessment Participation, current-year mean SGP,
  current-year weighted state-assessment proficiency, enrollment, resident
  districts, and the academic-achievement/growth halves of the performance
  overview. No board roster, contract term, or mission text — those stay
  SAMPLE (no backing resource; see Phase 2) and are intentionally left off
  so this is the first report in the library presentable as complete
  rather than partly illustrative. Compliance/Financial Reporting
  Condition pills are excluded for the same reason (100% SAMPLE, no
  resource at all).
- **Extracted `Emisint.Reports.School.SchoolSnapshot`** — the real-data
  loaders (entity identity, enrollment, resident districts, School Index,
  SGP, weighted proficiency, and the real half of the performance-overview
  ratings) used to be private to `PerformanceReportPdf`; now shared between
  it and `BoardSummaryPdf` via `SchoolSnapshot.load/2`, so both reports read
  from one source instead of two independently-drifting copies of the same
  MDE queries (mirrors the existing `EdRegression.for_display/2`
  precedent). `PerformanceReportPdf` was refactored to call this module for
  those fields and merge its own SAMPLE fields on top — pure refactor, its
  existing test passes unmodified.
- **2 new smoke tests** (`test/emisint/reports/school/board_summary_pdf_test.exs`),
  same real-data/empty-database pattern as every other report test — full
  `test/emisint/reports/` suite is 16/16 passing.
- **Verified live**: generated a real PDF via `mix run` from dev-DB data
  (school code `03868`) — confirmed exactly 1 page, valid `%PDF-1.7`.
  Also hit `GET /mde/board-summary.pdf?building=03868&year=...` against a
  running `mix phx.server` and got back the same 1-page PDF end-to-end
  through the router/controller, not just the bare module.
- **Found, not fixed (pre-existing, unrelated)**: at the start of this
  session, `git status` showed ~50 files outside this plan's scope already
  modified on disk (e.g. `lib/emisint/accounts/organization.ex`,
  `lib/emisint/assessments/mde_district.ex`, several `test/emisint/*`
  files) — confirmed via file mtimes to predate this session's first edit,
  so not something this session's `mix format` caused. Matches the same
  "unscoped `mix format`" failure mode flagged in the 2026-07-30 Phase 0
  entry below; left untouched and unformatted this time since it's out of
  scope — flagging here so a future session doesn't mistake it for new
  work.

### Shipped 2026-07-30 — Phase 0 (design-system consolidation) complete

Full session summary — see the "Phase 0" checklist below for the
item-by-item detail; this is the narrative version.

**What got built:**
- New `priv/typst/shared/design_system.typ`: color tokens, `to-num`/
  `to-bool`/`disp-str` coercion, formatting helpers, `th`, both section-
  heading styles (`section-heading` centered / `section-title` left-bar),
  `stat-box`, `detail-row`, every badge variant (`pct-badge`,
  `delta-badge`, `delta-badge-between`, `sgp-badge`, `mini-badge`,
  `score-cell`, `status-pill`, `quadrant-badge`), and every chart
  primitive (`pie-chart`, `gauge`, `horizontal-bars`, `line-chart`,
  `heatmap-table`, `regression-chart`, `monogram`/`decorative-band`).
- All 6 in-scope templates (`performance_report.typ`,
  `regression_report.typ`, `sss_comparison.typ`, `crd_comparison.typ`,
  `school_vs_lea.typ`, `portfolio.typ`) migrated to `#import
  "/shared/design_system.typ": *`, with per-template local aliases where
  a template's body used an old color name — no template's own visual
  content/layout changed except where called out below.
- **Chart/badge palette now matches the live dashboard**: converted the
  app's real DaisyUI theme colors (light-mode OKLCH values in
  `assets/css/app.css`) to sRGB and made those the canonical
  `c-success`/`c-warning`/`c-error` tokens, used for the ED%-vs-
  performance regression quadrants *and* every other status color
  (proficiency badges, rating pills, SGP badges). This is a visible,
  intentional change — PDF "green" shifted from forest-green (`#15803d`)
  to the app's teal-green (`#009689`), "red" from `#b91c1c`/`#dc2626` to
  crimson (`#ea003e`). Trivial to revert by editing the 3 token lines in
  `design_system.typ` if it's not liked in practice.
- **`portfolio.typ` migrated conservatively, on purpose**: only coercion
  helpers and the regression chart's colors were unified; page size (A4),
  margins, typography, and the no-footer layout were deliberately left
  alone since a layout change needs visual PDF rendering to verify, which
  wasn't available this pass. Flagged in the Phase 0.4 checklist item.
- **Fake "APM" logo boxes replaced** with the real `emisint_small_logo.png`
  asset in `crd_comparison.typ`, `sss_comparison.typ`, `school_vs_lea.typ`
  (`performance_report.typ` already had it; `portfolio.typ` never had a
  logo mark to begin with; `comprehensive.typ` intentionally untouched).
- **14 new smoke tests** (`test/emisint/reports/**`), one file per report
  module, each with a real-data case and an empty-database case — this
  is genuinely the first test coverage any PDF report has ever had in
  this codebase.
- **Real bug found and fixed**: `school_vs_lea.typ`'s old local
  `delta-badge` checked `v == none` *before* coercing the value, so it
  never caught Elixir `nil` (which arrives as the Typst string `"nil"`,
  not `none`) — this crashed PDF compilation
  (`"cannot compare none and integer"`) any time a subject/grade cell had
  no LEA comparison value, which is a normal, expected data state (not an
  edge case). Caught by the new empty-database smoke test; fixed in the
  shared `delta-badge` (coerce-then-check, per the typst skill's
  documented pattern).
- **Environment fix required to run any of this**: `config/test.exs` —
  untouched since the repo's very first commit — had no Postgres `port`
  override, so `mix test` couldn't connect to a database at all in this
  dev environment (Postgres only listens on 5433 here, not the default
  5432; `config/dev.exs` already had the override, `test.exs` never did).
  Added `port: 5433` to match.
- **Discovered, explicitly not fixed**: running the full `mix test` suite
  (now possible for the first time thanks to the port fix above) surfaced
  ~150 pre-existing failures, all in `Emisint.Registry.*`,
  `Emisint.Compliance.*`, `Emisint.Analytics.*`, `Emisint.Accounts.
  SchoolTest`, old generic `Emisint.Assessments.{BenchmarkProvider,
  AssessmentResult}Test`, and the `Emisint.Workers`/`Emisint.Integration`
  worker/pipeline tests — every one of them references an Ash
  resource/domain that no longer exists in `lib/` (deleted in the
  "resource_cleanup" PR mentioned in `PLAN_lua_poc.md`, which only flagged
  a narrower slice of this same rot). Confirmed unrelated to this session
  — none reference anything touched here, and all 49 previously-passing
  tests (including the 14 new ones) still pass. Worth a dedicated cleanup
  PR (delete the orphaned tests, or resurrect the resources if those
  domains are still wanted) — out of scope for this plan.
- **Process note**: an early unscoped `mix format` run reformatted ~45
  files with no relation to this work (touched via Styler's project-wide
  pass, not by hand). Caught via `git status` before finishing and
  reverted everything outside this session's actual scope — final diff
  is exactly the files listed above, nothing else.
- **Verified live**: started `mix phx.server` and generated a real PDF
  from dev-DB data (`Emisint.Reports.School.SssComparisonPdf`, school
  code `03868`, confirms the shared partial + real logo + new palette all
  compile and render correctly outside the test suite too, not just
  under `Ash.create!` fixtures).

### Shipped 2026-07-29

- **Fixed a real bug**: the school-level reports used to hardcode
  `"Grand Valley State University"` as the authorizer for every school
  regardless of who actually charters it. `org_name` now reads the real
  `entity_chartering_agency_name` per school
  (`performance_report_pdf.ex`).
- **New: School Performance Report** (8-page, landscape) —
  `lib/emisint/reports/school/performance_report_pdf.ex` +
  `priv/typst/school/performance_report.typ`, wired to
  `GET /mde/performance-report.pdf` via
  `EmisintWeb.MdePerformanceReportController` and a "Full Performance
  Report" button on the School vs LEA tab. Modeled on the reference layout
  documented below (originally an authorizer's real report format,
  genericized). Real vs. sample data is explicitly marked in the module —
  see "Data completeness" below; this is the **first entry in the future
  template library** (item 2 in the vision above), not yet built from
  shared components.
- **New: dedicated Regression PDF for ESP Portfolios** —
  `lib/emisint/reports/portfolio/regression_pdf.ex` +
  `priv/typst/portfolio/regression_report.typ`, wired to
  `GET /esp-portfolio/regression.pdf`. Bigger M-STEP and SAT scatter charts
  than the version buried in the combined Portfolio PDF, plus a full
  supporting-data table (every school, ED%, value, "beating the
  odds"/"as expected"/"underperforming" classification) with numbered dots
  on the chart matching numbered rows in the table — the static-PDF
  equivalent of the live dashboard's hover tooltips. The ESP Portfolio
  "Download PDF" button is now tab-aware: it links here when the Regression
  tab is active, and to the full portfolio PDF otherwise.
  **Explicitly scoped to ESP Portfolios only** — a linear-regression
  section was prototyped in the School Performance Report and in this
  Regression PDF (as a 3rd "SGP vs ED%" chart) and **removed from both** per
  product direction: schools shouldn't see their management company's whole
  portfolio, and SGP-vs-ED% specifically didn't belong here at all once SGP
  landed in the right place (see next item).
- **Added the SGP section that was missing from the School vs LEA PDF** —
  the live "School vs LEA" dashboard tab has shown Student Growth Percentile
  (SGP) by subject and by grade for a while; the PDF export
  (`school_vs_lea_pdf.ex` / `school_vs_lea.typ`) didn't include it at all.
  Added a subject-summary table (School vs. LEA mean SGP, color-coded by the
  standard growth bands) and a full by-grade breakdown table, using the same
  weighting logic as the live dashboard so the two can't drift apart.
- **Extracted `EdRegression.for_display/2`** — a shared formatter now used
  by both the full ESP Portfolio PDF and the dedicated Regression PDF, so
  the regression chart/table shape has one source of truth instead of two
  copies. (Small, scoped win — not the full design-system consolidation
  Phase 0 below still calls for.)
- **Replaced fake "campus photo" placeholders** with a branded
  gradient-and-monogram divider (school initials, e.g. "ACA" for Achieve
  Charter Academy) in the Performance Report — a real photo per school
  isn't realistic to source, so this keeps the reference design's visual
  rhythm without pretending to be a stock photo.
- **Two real bugs found and fixed**: a Typst `rect(height: 100%)` inside a
  `grid` was self-referentially expanding to fill entire pages (caused
  runaway page counts — 10 pages instead of 8); the SGP source table stores
  `school_year` as `"24 - 25 School Year"` while the School Index table uses
  `"2024-2025"` — using the wrong format silently returned zero rows instead
  of erroring, which is why this needed active debugging rather than being
  obvious from a stack trace.
- **Confirmed SSS (Statistically Similar Schools) data is real** for
  GVSU-authorized schools (398 schools / 68 comparison groups, imported via
  "GVSU SSS - Consolidated.csv") and wired the Performance Report's peer
  roster to use it when available, falling back to sample data for schools
  with no SSS group on file. MDE's SSS source file has no
  inter-school-distance column at all — that field is `nil`/`"—"` for real
  rows, never fabricated, for any school.

### What's still true from the original audit — updated 2026-07-30

Phase 0 (2026-07-30) resolved every item that used to live in this
section. What's left, now that the design system exists:

- **`comprehensive.typ` is still an orphaned prototype** (448 lines, no
  Elixir module wiring it up) — decision made 2026-07-30 to leave it
  exactly as-is (see Phase 0.5 below); still not migrated to the shared
  partial, still not deleted, still not wired up. Only remaining
  open-ended item from the original audit.
- **`portfolio.typ`'s page size/margins/typography/footer are still the
  outlier** — deliberately not touched in the 2026-07-30 migration (see
  Phase 0.4 below); it now shares coercion + regression-chart colors with
  everything else, but its physical layout is still its own thing. Needs
  visual PDF rendering to verify before attempting, which wasn't available
  this pass.
- **No visual QA tooling exists in this environment** — every check this
  session was "does it compile and return PDF bytes," not "does it look
  right." A real screenshot/render-diff step is still missing for Phase 4.

Resolved as of 2026-07-30: shared design-system partial exists
(`priv/typst/shared/design_system.typ`); `to-num`/boolean coercion is
consolidated there (matching `.claude/skills/typst/SKILL.md`); chart
primitives (gauge/pie/line/regression-scatter) are consolidated there;
smoke-test coverage exists for all 7 `generate_report/2` functions.

### Data completeness (real vs. sample, Performance Report)

Tracked in detail in `performance_report_pdf.ex`'s moduledoc; summarized
here since it blocks calling any template "done":

**Real, from MDE imports:** school identity/address/grades/open date, ESP
name, current-year enrollment totals + subgroup %, resident district
breakdown, School Index + Participation + support category (current year),
weighted M-STEP proficiency (current year, School + State), current-year
mean SGP, SSS peer roster (where imported).

**Sample/placeholder — no backing resource exists yet:** board members,
charter contract term length/expiration year, Compliance/Financial
Reporting Condition ratings, school mission statement, attendance rate,
5-year history for every trend chart (enrollment, achievement-vs-peer,
growth-vs-peer, proficiency-vs-peer — only one school year of data exists
in this environment at all), SSS peer distance-in-miles (not published by
MDE at all, not just unimported).

## Phased plan

### Phase 0 — Consolidate the design system (foundation, do this first)

Everything from the original audit, unchanged in substance, now with more
urgency since 2 more templates exist:

- [x] **0.1 Extract a shared Typst design-system partial** — done:
      `priv/typst/shared/design_system.typ`. Color tokens, `to-num`/`to-bool`/
      `disp-str` coercion, formatting helpers, `th`, `section-heading` +
      `section-title` (two distinct visual styles, both kept), `stat-box`,
      `detail-row`, badges (`mini-badge`/`pct-badge`/`score-cell`/
      `delta-badge`/`delta-badge-between`/`sgp-badge`/`status-pill`/
      `quadrant-badge`), and chart primitives (`arc-points`/`pie-chart`/
      `pie-legend`/`gauge`/`horizontal-bars`/`line-chart`/`chart-legend`/
      `heatmap-table`/`regression-chart`/`monogram`/`decorative-band`).
      Imported via `#import "/shared/design_system.typ": *` into all 6
      in-scope templates (`comprehensive.typ` excluded per 0.5's decision).
      Required adding `root_directory: Application.app_dir(:emisint,
      "priv/typst")` to every `*_pdf.ex` module's `Imprintor.Config.new/3`
      call (6 of 7 had no `root_directory` at all, defaulting to `"."` —
      harmless in dev/test where cwd is the repo root, but not
      release-safe; now fixed everywhere, and a prerequisite for
      Typst's `#import "/...")` absolute-path resolution to work).
- [x] **0.2 Consolidate `to-num`/boolean coercion** into the shared
      partial, matching `.claude/skills/typst/SKILL.md`'s canonical
      version. **Found and fixed a real bug in the process**:
      `school_vs_lea.typ`'s old local `delta-badge` checked `v == none`
      *before* coercion, so it never caught Elixir `nil` (which arrives as
      the string `"nil"`) — this crashed Typst compilation
      (`"cannot compare none and integer"`) any time a subject/grade cell
      had no LEA comparison value. Caught by the new 0.7 smoke test's
      empty-database case; fixed in the shared `delta-badge`.
- [x] **0.3 Consolidate chart-drawing logic** — regression-scatter,
      gauge, pie/donut, and line-chart primitives unified into the shared
      partial (one `regression-chart` used by `portfolio.typ`,
      `regression_report.typ`, and `esp_portfolio_pdf.ex`'s embedded
      section, parameterized by `chart-h`/`numbered`/`dot-radius` instead
      of 2-3 near-duplicate implementations). **Decided 2026-07-30: yes**,
      match the LiveView `scatter_chart.ex` quadrant palette — converted
      the app's actual live DaisyUI theme colors (light-mode OKLCH values
      in `assets/css/app.css`) to sRGB and used those as the canonical
      `c-success`/`c-warning`/`c-error` tokens, applied to the regression
      quadrants *and* every other status color (proficiency badges,
      "Exceeds Standard" pills, SGP badges) for one consistent traffic-light
      vocabulary across the whole system. Net effect: PDF "green" shifted
      from forest-green (`#15803d`) to the app's teal-green (`#009689`),
      "red" from `#b91c1c`/`#dc2626` to crimson (`#ea003e`) — flagging
      since it's a visible, subjective change; easy to revert to the old
      hex values in `design_system.typ` alone if you'd rather keep them.
- [x] **0.4 Rework `portfolio.typ`** onto the shared design system —
      **done with intentionally conservative scope**: coercion helpers
      (`to-num`/`to-bool`/`fmt-pct`/`fmt-delta-pp`/`fmt-delta-pts`) and the
      ED%-vs-performance regression chart now come from the shared partial
      (so its colors match the live dashboard). Page size (A4, not
      `us-letter`), margins, typography (no explicit font), and the
      no-footer layout were deliberately **left untouched** — this is the
      highest-traffic, highest-risk template (chartering-agency + ESP
      portfolio flows) and a layout change needs visual PDF rendering to
      verify, which wasn't available this pass. Revisit as a follow-up if
      full visual parity with the other templates is wanted.
- [x] **0.5 Resolve the `comprehensive.typ` orphan** — **Decided
      2026-07-30: leave it as-is (Option C).** It predates this branch
      (added on `main` in commit `ecf3a64`/`2227509`/`8f8ff9c`, 2026-02-26,
      by Sundar Nambuvel — confirmed identical between `main` and
      `betterPDF`, never had a matching `.ex` loader). User has full
      authority over PDF generation now and confirmed with Sundar directly,
      but wants the file kept untouched in case it's wanted later. **Do
      not** migrate it onto the shared design-system partial in 0.1/0.3,
      do not delete it, do not wire it up — out of scope for Phase 0
      entirely.
- [x] **0.6 Replace fake logo marks** with the real
      `emisint_small_logo.png` asset — done in `crd_comparison.typ`,
      `sss_comparison.typ`, `school_vs_lea.typ` (`performance_report.typ`
      already had it; `portfolio.typ` never had a logo mark to begin
      with; `comprehensive.typ` untouched per 0.5).
- [x] **0.7 Add smoke-test coverage** for all `generate_report/2`
      functions (assert `{:ok, <<pdf bytes>>}` for representative
      fixtures), including nil/string-boolean coercion edge cases. Do this
      *before* 0.1–0.4 land if possible, so the consolidation has a
      regression net rather than relying on manual visual QA alone.

### Phase 1 — Expand the template library

Only meaningfully different from copy-pasting more one-off files if built
on top of Phase 0's shared components:

- [x] **1.1 Build a second distinct visual preset** (different layout
      philosophy from the Performance Report's landscape/branded style —
      e.g. a compact single-page board-summary format) using shared
      components from Phase 0, to prove the "compose from shared parts"
      pattern repeats before investing further. **Done 2026-07-30**: the
      one-page "Board Summary" report (see the shipped entry above) —
      built entirely from existing `design_system.typ` components, no new
      chart primitives needed, confirming the pattern repeats.
- [ ] **1.2 Decide `comprehensive.typ`'s fate** (ties to 0.5) — if it
      becomes a real report, it's a natural 3rd preset (KPI-card-heavy
      style already built). **Re-confirmed deferred 2026-07-30** — same
      call as 0.5, kept as-is, no action. Revisit only if there's an
      actual reason to (e.g. someone asks for a KPI-card-heavy report
      style).
- [x] **1.3 Catalog the section library** — enumerate every distinct
      "section" that exists across all templates today (enrollment
      donut, M-STEP table, SGP summary, School Index gauge, board table,
      peer roster, regression chart, etc.) as the literal menu of choosable
      blocks Phase 3's picker will offer. **Done 2026-07-30** — see
      "Section Library Catalog" below.

### Phase 2 — Close real data gaps

Needed before any template can be presented to a client as complete rather
than partly illustrative:

- [ ] **2.1 Board Member data** — no resource exists; needs a new Ash
      resource + admin UI to enter/import board rosters per school.
- [ ] **2.2 Charter Contract data** — term length, expiration year;
      CLAUDE.md's domain table describes `CharterContract`/
      `Schedule71Goal`/`GoalEvaluation` resources that were never actually
      implemented (only an orphaned DB migration exists). This is real
      resource-modeling work, not a quick fix.
- [ ] **2.3 Compliance/Financial Reporting Condition** — no resource
      exists; needs a defined rating methodology (who sets it? on what
      basis?) before it can be anything but sample data.
- [ ] **2.4 School mission statement** — add a field (likely on the
      `School`/`Organization` resource) and an admin UI to set it.
- [ ] **2.5 Multi-year history** — only one school year of MDE data
      exists in this environment; every trend chart needs either more
      imported years or an explicit "insufficient history" state instead
      of sample-filled charts, once more years are actually imported.
- [ ] **2.6 SSS distance-in-miles** — MDE's source file doesn't publish
      this at all; flag as a known limitation, not a backlog item, unless
      a different data source is found.

### Phase 3 — Build the customization engine

The actual "client picks sections + format" system:

- [ ] **3.1 Design the config schema** — per-client (or per-report-request)
      selection of which sections to include and which template/format to
      render them in.
- [ ] **3.2 Backend composition logic** — a report generator that reads
      the config and assembles the chosen sections from the Phase 1
      library into one PDF, replacing today's one-fixed-shape-per-report
      model.
- [ ] **3.3 Picker UI** — LiveView interface for an admin to choose
      sections/format, preview, and save the choice (per client, reusable
      across report runs).
- [ ] **3.4 Persistence** — store a client's report configuration so it
      doesn't need re-selecting every time.

### Phase 4 — Testing, polish, rollout

- [ ] **4.1 Visual QA pass** across every template/section combination
      the picker can produce, not just the fixed reports that exist today.
- [ ] **4.2 Deprecate/retire old ad hoc reports** once their sections are
      fully represented in the Phase 1 library and Phase 3 picker can
      reproduce them.
- [ ] **4.3 Documentation** for admins on how to configure/generate a
      customized report.

## Section Library Catalog (Phase 1.3)

Every distinct visual section across the 7 in-scope templates (excludes
`comprehensive.typ`, cataloged separately below since it has no backing
loader at all), grouped by subject area so it can double as the literal
menu Phase 3's picker offers. "Shared component(s)" names the
`design_system.typ` building block(s) each section is built from — a blank
means it's still a template-local, one-off implementation (e.g. `tri-bar`,
`index-row`) that Phase 3 would need to either promote to the shared
partial or accept as template-specific chrome.

**Identity / header**
- School details panel (`detail-row` grid) — REAL — `sss_comparison`,
  `school_vs_lea`, `crd_comparison`
- Cover / branding header (logo + title + org strip) — REAL —
  `performance_report`, `board_summary`

**Enrollment**
- Enrollment KPI pair, Total/Econ. Disadvantaged (`stat-box`) — REAL —
  `school_vs_lea` (school scope and LEA scope, twice)
- Resident-districts donut (`pie-chart`+`pie-legend`) — REAL —
  `performance_report`, `board_summary`
- Subgroup enrollment bars (`horizontal-bars`) — REAL current-year /
  SAMPLE attendance figure — `performance_report`
- 5-year enrollment trend (`line-chart`) — SAMPLE (current year real,
  4 prior years placeholder) — `performance_report`
- Enrollment-by-grade-by-year (`heatmap-table`) — SAMPLE history, REAL
  current year — `performance_report`

**Proficiency / achievement**
- Tri/bi-compare bar rows, school vs. LEA/state/peer group (local
  `tri-bar`/`bi-bar` + `mini-badge`/`delta-badge-between`) — REAL —
  `sss_comparison`, `school_vs_lea`, `crd_comparison`
- M-STEP composite reference table (`pct-badge`) — REAL —
  `sss_comparison`, `crd_comparison`
- Proficiency-by-subject table (`pct-badge` + local `tri-bar`) — REAL —
  `school_vs_lea`
- Grade-level breakdown table, all-students + Econ. Disadvantaged variant
  (`pct-badge`, supports the `approximate` FERPA-suppression flag) —
  REAL — `school_vs_lea`
- Peer-school roster, M-STEP scores (`pct-badge`) — REAL —
  `sss_comparison`, `crd_comparison`
- Achievement-vs-peers-over-time (`line-chart`) — SAMPLE —
  `performance_report`
- Proficiency trends by subject, School/State/Peer 3-series
  (`line-chart`+`chart-legend`) — SAMPLE history, REAL current year
  spliced in — `performance_report`
- Compact proficiency & growth snapshot table (`pct-badge`+`sgp-badge`) —
  REAL — `board_summary`
- MI state-test-by-grade static reference table — static, not
  per-school data — `performance_report` appendix

**SAT**
- Tri/bi-compare bar rows + composite table (`score-cell`) — REAL —
  `sss_comparison`, `crd_comparison`
- SAT results by subgroup + score bars (local `sat-score-bar`) — REAL —
  `school_vs_lea`
- Peer-school roster, SAT scores (`score-cell`) — REAL —
  `sss_comparison`, `crd_comparison`

**Growth (SGP)**
- SGP subject-summary table, school vs. LEA (`sgp-badge`) — REAL —
  `school_vs_lea`
- SGP by-grade table (`sgp-badge`) — REAL — `school_vs_lea`
- Growth-vs-peers-over-time, ELA + Math (`line-chart`) — SAMPLE —
  `performance_report`
- Current-year mean SGP callout — REAL — `performance_report`

**School Index / Participation**
- School Index score, bar + threshold tick (local `index-row`, not the
  shared `gauge`) — REAL value / threshold effectively unavailable
  (`mde_index_thresholds` has 0 rows) — `school_vs_lea`
- School Index gauge (`gauge`) — REAL value / SAMPLE threshold —
  `performance_report`, `board_summary` (board_summary omits the
  threshold caption entirely rather than showing a SAMPLE number, per
  its real-data-only scope)
- Assessment Participation gauge (`gauge`) — REAL value, real 95%
  federal policy constant — `performance_report`, `board_summary`

**Peer / comparative**
- Statistically Similar Schools roster — REAL if an SSS group is on
  file for the school, else SAMPLE fallback — `performance_report`
- District-to-Academy portfolio delta bars, M-STEP + SAT vs. LEA, one
  bar per school (`stat-box` + local `bar-row`) — REAL — `portfolio`
- ED% vs. performance regression scatter + numbered supporting table
  (`regression-chart`, `with-index`, `quadrant-badge`) — REAL
  (`Emisint.Assessments.EdRegression`) — lives only in `regression_report`
  now (ESP-Portfolio-only, per product decision — see Notes). Used to
  also exist as dead code in `portfolio.typ` (`PortfolioPdf.build_data/2`
  never set the `elixir_data.regression` key the template checked, so it
  could never render) — removed 2026-07-30, see the Phase 1.3 shipped
  entry above.

**Governance / compliance (100% SAMPLE — no backing resource exists)**
- Board member roster table — `performance_report`
- Contract term length / expiration year — `performance_report`
- Compliance/Financial Reporting Condition pills — `performance_report`
- Performance-overview status pills — Achievement/Growth are REAL
  everywhere they appear; Compliance/Financial are SAMPLE and only ever
  shown in `performance_report` (`board_summary` deliberately omits
  them — see its Phase 1.1 shipped entry)

**Appendix / static text**
- Academic/growth/compliance definitions — `performance_report`
- Financial definitions — `performance_report`
- Signature block — `school_vs_lea`, `crd_comparison`

**`comprehensive.typ` (orphaned prototype — no Ash resource, no loader,
no real data source for any section; deferred per 1.2)**
- Cover + contract summary strip
- KPI summary row (students assessed / goals on track / active triggers
  / data windows) (`stat-box`)
- State assessment proficiency by subject/window table (`pct-badge` +
  inline progress bar)
- SGP by grade/subject/window table
- Schedule 7-1 contractual-compliance goals table
- Active intervention triggers table (or a "no active interventions"
  success panel)
- Signature block

## Notes

- **Order dependency**: Phase 0 (especially 0.1 coercion/components and
  0.7 tests) should land before Phase 1's second preset, so the new
  template is built *from* shared pieces instead of adding an 8th
  copy-pasted set of tokens.
- **The `nil`→`"nil"`-string behavior is NIF-level** (confirmed in
  `imprintor`'s Rust source: Elixir atoms, including `nil`/`true`/`false`,
  convert to Typst strings). Phase 0.2 works within that constraint — it
  can't be "fixed" upstream from this codebase.
- **CLAUDE.md's "Reauthorization Packet Generator" and "Board Report
  Builder"** (PRD section 3.5, tracked separately as Phase 8 in the master
  `PLAN.md`) are unbuilt PRD items, related to but not the same as this
  plan — likely consumers of the Phase 3 customization engine once it
  exists.
- **Regression is explicitly ESP-Portfolio-only, by product decision** —
  don't re-add it to school-level reports (Performance Report or any future
  school-facing template) without an explicit ask; the underlying reason
  (schools shouldn't see their management company's whole portfolio) is a
  product/privacy decision, not a technical limitation.
- **Resolved 2026-07-30**: the reference layout below is now cross-indexed
  by the "Section Library Catalog" (Phase 1.3) above — the catalog is the
  structured, per-section REAL/SAMPLE breakdown; this prose section stays
  as the original full-page-by-page design spec it was written against.
- **`config/test.exs` was missing a Postgres `port` override** (the
  Postgres instance in this dev environment only listens on 5433, per
  `config/dev.exs`, but `config/test.exs` — untouched since the very first
  commit — defaulted to Postgrex's standard 5432). Fixed by adding
  `port: 5433` to match. This means `mix test` could not connect to a
  database at all before this fix; it's unrelated to this plan but was
  blocking the 0.7 smoke tests from running, so it had to be fixed first.
- **Found ~150 pre-existing, unrelated test failures running the full
  suite** (`mix test`) after the above port fix — every one of them is in
  `Emisint.Registry.*`, `Emisint.Compliance.*`, `Emisint.Analytics.*`,
  `Emisint.Accounts.SchoolTest`, `Emisint.Assessments.{BenchmarkProvider,
  AssessmentResult}Test`, `Emisint.Workers.{CsvImportWorker,
  SnapshotRefreshWorker,GoalRecalculationWorker}Test`, and
  `Emisint.Integration.{CsvImport,DataPipeline}Test` — all referencing
  Ash resources/domains (`Emisint.Accounts.School`,
  `Emisint.Compliance.*`, `Emisint.Registry.*`, generic
  `Emisint.Assessments.BenchmarkProvider`/`AssessmentResult`) that no
  longer exist in `lib/` at all. This is orphaned test debt from the
  "resource_cleanup" PR referenced in `PLAN_lua_poc.md` (which flagged a
  narrower slice of this same issue) — the codebase pivoted entirely to
  concrete `Mde*`-prefixed resources under `Emisint.Assessments`, but
  these old test files were never removed. **Confirmed unrelated to this
  plan's changes** (none reference anything touched this session; all 49
  previously-passing tests, including the 14 new report smoke tests,
  still pass). Likely because `mix test` has never successfully connected
  to a database in this specific dev environment before now — nobody
  could have seen this failure count until the port fix above. Worth its
  own cleanup pass (delete the orphaned tests, or resurrect the resources
  if the Registry/Compliance/Analytics domains are still wanted) — out of
  scope here.

## Target Report Design (Reference Layout)

*(Implemented as the Performance Report in Phase "shipped this session"
above — kept here as the reference spec for that template, and as the
first candidate entry in Phase 1's future template library.)*

An eight-page, landscape-oriented, highly structured school performance PDF
that combines strong institutional branding with clean data visualization
(tables, charts, icons) and a consistent typographic hierarchy. The layout
below is modeled on an authorizer's existing report format we're demoing
against — organization- and school-specific text (logo, name, sample
values) has been genericized to placeholders (`{Org Name}`, `{School Name}`,
`{Org URL}`, etc.) since this is meant to describe the *format*, not any one
authorizer's or school's actual data.

### Overall document style

**Orientation and size**
- Landscape pages (~US Letter, 11x8.5).
- Generous top/bottom margins, with more whitespace at the bottom for footer elements.

**Color palette**
- Primary: a deep brand blue (headers, title bars, page strip).
- Accent: lighter blues (gradient backgrounds and chart series), plus orange for some charts.
- Status badges (e.g., "Exceeds Standard") use a bright green pill background with white text.
- Body and table text is dark gray or near-black.

**Typography**
- Header/title font: bold sans-serif (all caps or title case, strong weight).
- Body text: standard sans-serif, regular weight, left-aligned, single-column.
- Section headings: larger font size, blue, often center-aligned.
- Subheadings: slightly smaller, bold, usually left-aligned.

**Page structure**
- Each page begins with a centered report title line: "{Year} School Performance Report" followed by the school name on the next line.
- Content is organized into visually distinct blocks: top textual block(s), middle charts/tables, bottom image or footer bar.
- Page numbers appear in a colored strip at the bottom-left (e.g., "2"), and "{Org Name}" appears at bottom-right in a gray footer band.

### Cover page: branding and header elements

**Logo and header band**
- Large org logo/wordmark on a white background at the very top of the cover page.
- Below the logo, a bold centered title "{Year} School Performance Report" with a smaller line for the school name, e.g. "{School Name}".
- A vertical blue band on the right side with rotated white text ("{Org URL}").

**Bottom cover panel (school info + mission)**
- A full-width campus/school photo occupies the middle of the cover page.
- Under the photo, a white card-like area divided into two columns:
  - Left column: school address, city/state/ZIP, "Grades Served," "Contract Grades," "Year Opened," each on separate lines.
  - Right column: "School's Mission" heading in bold, followed by the mission text paragraph.
- A thin vertical colored bar to the left of the mission paragraph acts as a visual accent.

### Page 2: governance and summary status

**Top header bar**
- A full-width blue bar at the top listing "{Year} School Performance Report" and the school name, centered, in white text.

**Two-column key contract info**
- Under the header, contract information is presented as two large horizontal blocks:
  - Left: "Current Contract Term Length" with a value, e.g. "7 Years."
  - Right: "Contract Expiration Year" with a value, e.g. "2030."
- Labels are bold; values appear directly below, left-aligned.

**Educational Service Provider and Board table**
- "Educational Service Provider" is a bold label followed by the provider name text line.
- Board members are displayed in a grid-style table:
  - Columns: Name, Board Role, Appointed, Term Ends.
  - Each row alternates light shading to differentiate entries.
  - Bold header row with clear gridlines.

**Mid-page photo band**
- A rectangular aerial photo (campus or plaza) spans nearly the full page width below the table, acting as a visual break.

**Performance overview section**
- Centered heading: "{Year} School Performance Overview" in bold blue text.
- Below the heading, a vertical list of performance dimensions:
  - Compliance Reporting Condition
  - Financial Reporting Condition
  - Academic Achievement (M-STEP/PSAT)
  - Academic Growth (ELA, Math)
- Each label is followed by a green pill-shaped badge containing the performance rating (e.g., "Exceeds Standard").
- Text is centered horizontally on the page, with consistent vertical spacing.

### Page 3: enrollment and demographics

**Page heading**
- Same top text as other pages: report title + school name, centered and in blue.

**School Characteristics section**
- Heading "School Characteristics" centered in bold.
- Top row: two small charts
  - Left: "Student Resident Districts" — donut/pie chart of the top resident districts plus an "Others" bucket, with a legend and percent labels (e.g., 56%, 27%, 17%).
  - Right: "Subgroup Enrollment and Attendance" — horizontal bar chart with one bar each for Free-and-Reduced Lunch, Special Education, English Language Learners, and Attendance. Bars in grayscale/muted tones, percentage labels at the bar ends, left-aligned labels.
- Middle: enrollment trend line chart
  - Heading "5 Year Enrollment Trend."
  - Line chart, x-axis = school year (5 years), y-axis = "Enrollment" with numeric ticks.
  - Data points labeled with values and percent-change indicators (+1%, -2%, etc.).
- Bottom: enrollment by grade table
  - Heading "Enrollment by Grade and Year."
  - Heatmap-style table: rows K–8 plus a "Total" row, columns = the 5 school years, each cell a white number on a blue-gradient background (lighter at top, darker at bottom).
  - Footnotes: "* Data suppression" and "** Refer to year opened on cover."
- Standard footer strip (page number + org name).

### Page 4: peer schools and index

**Roster of Statistically Similar Schools**
- Heading centered in blue: "Roster of Statistically Similar Schools."
- Table with two columns: "Distance in Miles" and "Peer School Name." Styling matches the board member table (bold header, alternating row shading).

**School Index and Assessment Participation**
- Two side-by-side circular indicator charts:
  - Left: "School Index" — circular gauge/donut with a numeric value in the center (e.g., 99.25) and a "Minimum Threshold" label below.
  - Right: "Assessment Participation" — circular gauge with a percentage value and a "Minimum Required: 95%" marker.
- Text line: "MDE Designated Support Category: {Category}" beneath the charts.

**Bottom explanatory footnotes and photo**
- Two footnote paragraphs defining how the School Index threshold and Assessment Participation are calculated, referencing MDE and federal requirements.
- Large aerial photo band, same style as page 2.
- Standard footer strip.

### Page 5: contract performance trends

**Section heading**
- Centered heading: "Charter Contract Academic Performance Trends" in blue.

**Introductory paragraph**
- Left-aligned multi-line paragraph explaining that academic outcomes over time are central to contract renewal, encouraging boards/schools to discuss progress, and referencing the Appendix for calculation details.

**Achievement performance chart**
- Subheading: "Achievement Performance Compared to Peer Schools Over Time" (M-STEP/PSAT).
- Line chart: x-axis = years, y-axis = difference from peer schools (0 line, values above/below), one prominent line color, points labeled numerically.

**Growth performance charts (side-by-side)**
- Subheading: "Growth Performance Compared to Peer Schools Over Time."
- Two charts: "ELA" (orange line) and "Math" (blue line), both with year labels and numeric point values (Math includes negative values). Consistent axis/gridline style between the two.

**Bottom note**
- Small note explaining limited growth data due to missing/low-participation testing years and that elementary grades don't receive a growth score.
- "* Data suppression" footnote.
- Standard footer strip.

### Page 6: proficiency trends

**Section heading**
- Centered heading "M-STEP Proficiency Trends by Subject."

**ELA proficiency chart**
- Subheading in blue with an accent-colored "ELA" highlight: "M-STEP/PSAT ELA Proficiency."
- Three-series line chart: School, State, Peer Schools (each a distinct color), x-axis = years, y-axis = "Percent Proficient" (0–100). Each year's value labeled near the line.

**Math proficiency chart**
- Subheading "M-STEP/PSAT Math Proficiency" with "Math" in accent color.
- Same three-series line chart structure (School, State, Peer Schools).

**Footnotes and footer**
- "* Data suppression" note, standard footer strip.

### Pages 7–8: textual appendices

**Appendix heading**
- Both pages begin with a centered "Appendix" header, report title + school name above/below in smaller font.

**Page 7: academic and compliance definitions**
- "Academic Achievement:" — definition paragraph plus three bold-term/description pairs (Exceeds, Meets, Does Not Meet).
- "Academic Growth:" — similar structure describing SGP comparison to peer schools.
- "Compliance Reporting Condition Definitions:" — three bold terms with explanatory text.
- Single-column, left-aligned text; no charts on this page.

**Page 8: financial condition and test list**
- "Financial Condition Definitions:" — three bold labels (Exceeds, Meets, Does Not Meet Standards) with descriptive text.
- "Michigan State Tests by Grade" — compact reference table: rows by subject (ELA, Math, Social Studies, Science), each row listing grade ranges and test names (M-STEP, PSAT, SAT).
- Single column, left-aligned, same footer style as other pages.

### Structural elements to replicate in the generator

- **Global master page**: top centered title (report year + "School Performance Report" + school name); bottom gray footer band with "{Org Name}" on the right and a colored page-number strip on the left.
- **Consistent section patterns**:
  - Cover: logo + title + hero image + two-column card with school info and mission.
  - Page 2: contract overview (two-column key metrics), board table, mid-page image band, centered performance summary list with green status badges.
  - Page 3: demographic/enrollment charts (pie/donut, horizontal bar, line chart) plus a heatmap-style enrollment table.
  - Page 4: peer roster table, two circular KPI gauges, explanatory footnotes, bottom photo.
  - Pages 5–6: line charts for achievement/growth and proficiency trends with clear labels and numeric annotations.
  - Pages 7–8: appendix pages with definitions and simple reference tables, text only.
- **Visual consistency**:
  - All headings blue, centered or clearly separated from body text.
  - Pill-shaped labels with bright green background for categorical ratings.
  - Consistent legend ordering/colors across charts for School, State, and Peer Schools.
  - Consistent chart gridline style and axis font sizes across pages.
