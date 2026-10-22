# Plan: ND First School Goals Dashboard (Fort Yates pilot)

_Revision 4: Phase 1 (tasks 1–12) and Phase 2 (tasks 13–16, ND Insights import and display for Fort Yates) are implemented and tested. Phase 3 onward has not started._

## Approach

Add a new, state-agnostic **school improvement goals** feature: school → goal plan → goals → metrics → reporting periods. Values are stored as **append-only entries**. Fort Yates Middle School is seeded from a hand-transcribed data module (not the workbook itself). The other seven ND First schools reuse the same structures later with only new seed data.

Three kinds of numbers live in **separate resources** and are never derived from each other:

| Kind | Resource | Scale | Used for |
|---|---|---|---|
| Actual metric result | `ActualResult` | metric unit; percent normalized to 0–1 | display vs baseline/targets |
| Seasonal implementation rating | `ImplementationRating` | 0–3, N/A, or unavailable | seasonal averages |
| Formal review rating | `ReviewRating` (Phase 3) | 0–3 or N/A | payment calculation only |

Because actual results and ratings are separate records, an actual-only update can never erase a displayed rating, and a rating-only update can never erase a displayed actual. Each displayed value carries its own period, source, author, and timestamps.

Public state data (ND Insights CSVs) goes in its own global table. Imports never write to school entries.

### Codebase facts (verified)

- **Domains:** only `Accounts` (User, Token, Organization, ApiKey), `Assessments` (Michigan `Mde*`, global/non-tenant), and `Chat`. There is no `School`, `Registry`, `Compliance`, or `Analytics` code in `lib/`, although orphaned tests for them exist under `test/emisint/`.
- **No resource uses Ash multitenancy or AshPaperTrail yet.** These are the first `strategy :attribute` tenant resources.
- **Users:** one `organization_id` and one `role`. A new `SchoolMembership` provides school-level access.
- Tenant comes from `EmisintWeb.LiveScope` / `Emisint.Scope`. System admins switch org via `session["admin_org_id"]`.

### Source verification

- The Insights dashboard for `4300429212` shows **"Fort Yates Middle School"**, district **"Ft Yates Public School District"**, grades 5–8. This matches PDF p.17.
- **Not yet verified against a downloaded CSV.** `ShowFile` downloads are JS-driven and return an empty HTML stub to curl, so a browser download is needed (Task 13).
- The Data page lists Assessment Performance, Participation, **Growth Rate**, and **Engagement Survey** datasets. Only the Performance and Participation columns have been seen. Growth and Engagement schemas, and whether they contain Fort Yates rows, still need inspection.
- PDF p.3 links ID `1700308503`, which is not Fort Yates. It is not used.

---

## Data structures

All tenant resources use `multitenancy strategy :attribute, attribute :organization_id`, carry a denormalized `school_id` (for simple policies), and never accept `:organization_id`. **Parent scope is derived, not accepted:** creating a child copies `school_id` / `goal_plan_id` / `metric_id` from a parent loaded *inside the caller's tenant*, so a forged ID from another organization or school fails with "not found".

### Accounts

- **`School`**: `name`, `short_name`, `slug`, `state`, `state_entity_id`, `district_name`, `grade_span`, `active`. Identities: `[:slug]` and `[:state, :state_entity_id]` (per tenant). Created by seed only. There is no update action yet.
- **`SchoolMembership`**: `user_id`, `school_id`, `role` (`:viewer | :contributor | :reviewer`). The user's `organization_id` must equal the tenant, and the school must exist in the tenant. Identity `[:user_id, :school_id]`.

### Improvement domain (definitions are read-only in the pilot: create via seed, no update or destroy actions)

- **`GoalPlan`**: `program` ("nd_first_mou"), `name`, `definition_version` (1), `progress_doc_url`, `payment_cap` (70000), `systems_weight` (0.70), `outcomes_weight` (0.30), `max_rating` (3), `source_note`.
- **`Goal`**: `number`, `title`, `description`, `implementation_steps` (map period code → planned step count), `source_ref`.
- **`Metric`**: `code`, `description`, `category` (`:systems | :student_outcome`), `unit` (`:percent`), `direction` (`:higher_is_better | :lower_is_better`), `performance_measure` (`:proficient | :novice | :met_growth_expectation | :other`; "Proficient" is never equated with "Proficient or Advanced"), `baseline_value`, `target_18m`, `target_36m` (normalized, **0–1 enforced** for percent; nullable), `source_values` (map of original cells: `%{"target_36m" => %{"cell" => "P7", "raw" => "90"}}`), `flags` (e.g. `[:target_36m_needs_confirmation]`), `position`.
- **`ReportingPeriod`**: `code`, `label`, `kind` (`:seasonal | :review_18m | :review_36m`), `position`, `source_column`, `starts_on` / `ends_on` (unknown, nullable).
- **`AnnualAssessmentGoal`**: `school_year`, `subject` (`:ela | :math`), `target_value` (0–1), `measure` (`:proficient_or_advanced`), `includes_alternate`, `source_ref`.

### Entries (append-only; `ActualResult` and `ImplementationRating` share the same model)

- `kind`: `:observation` (the first value for a metric × period) or `:correction` (replaces exactly one current entry).
- `corrects_id`: for a correction, this must reference the **current** entry. Scope (school, metric, period) is copied from it and must match any supplied values.
- **Concurrency:** a unique index on `corrects_id` means two corrections of the same entry can't both succeed. The second is rejected with "already corrected; reload and correct the latest entry". A partial unique index on `(metric_id, reporting_period_id) WHERE kind = 'observation'` means a second observation is rejected rather than racing. **"Current" is defined structurally (no entry corrects it), never by timestamp.**
- **Provenance:**
  - `source` (`:manual | :workbook_import`), `source_ref` (e.g. `Ft Yates Goals!E4`), `source_last_updated_on` (the workbook's 2026-08-18)
  - `author_id` (original author; **nil when unknown**)
  - `recorded_by_id` (actor who created the row; nil if none)
  - `recorded_at` (server timestamp, never user-supplied)
  - `measurement_date` (nullable; never invented)
  - `notes`, `evidence_links` (embedded `{url, label}`, http/https only), `correction_reason` (required for corrections)
- **`ActualResult.value_state`**:
  - `:exact`: `value` required
  - `:range`: `range_low` ≤ `range_high`
  - `:suppressed`: no value; optional `suppression_reason`, kept verbatim from the source
  - `:unavailable`: no value; `notes` explanation required
- **`ImplementationRating.rating_state`**: `:rated` (`score` 0–3 required), `:not_applicable`, or `:unavailable` (`notes` required). Only `:seasonal` periods are allowed.
- **`ReviewRating`** (Phase 3) follows the same entry model for `:review_18m` / `:review_36m` periods.

### Payment (Phase 3, plain module)

`((avg Systems review × systems_weight + avg Outcomes review × outcomes_weight) / max_rating) × payment_cap`, using the plan's stored weights (0.70 / 0.30 is the working rule).

- **Category totals are counted from the plan's metrics**, not hard-coded (Fort Yates happens to have 8 and 10).
- Missing, N/A, and unavailable ratings are excluded, never treated as zero.
- An amount is shown only when each category has ≥1 rating. Otherwise the card says "Awaiting review".
- A partially rated plan shows the amount labeled **Provisional**.
- Metrics whose targets need confirmation are excluded from any target comparison.

### `Assessments.NdAssessmentResult` (Phase 2, global)

There will be **one table per Insights dataset schema**, or a shared header table plus dataset-specific measure columns. The performance-level Low/High columns are not reused for Growth Rate or Engagement Survey until those schemas are inspected. Common fields: `source`, `dataset`, `academic_year`, `institution_id`, `institution_name`, `grade`, `subject`, `assessment_type`, `accommodations`, `subgroup`, `raw_row`, `source_file`, `import_log_id`, and a per-measure state (`exact | range | suppressed | unavailable`) with a **verbatim** source suppression reason when given. The UI shows the stated reason, or otherwise "Suppressed" or "Unavailable"; it never assumes "n<10". Upserts are idempotent on the natural key.

---

## Permissions (implemented with the resources, not deferred)

| Actor | Read school data | Record/correct actuals and ratings | Manage memberships |
|---|---|---|---|
| `system_admin` | yes, in whichever tenant is selected (org switching) | yes | yes |
| `emo_admin`, same org as record | yes, all schools in org | yes | yes |
| membership `:contributor` | that school only | that school only | no |
| membership `:viewer` / `:reviewer` | that school only | no (reviewer rates in Phase 3) | no |
| anyone else (no membership, or another org) | no | no | no |

- Every non-admin check also requires `actor.organization_id == record/tenant organization`. A user whose `organization_id` doesn't match the tenant sees nothing, even if a forged tenant is passed.
- Definition resources accept creates only from system admins or seeds (`authorize?: false`).

## Seeding and the workbook import

- `mix nd_first.seed --organization-id <uuid> [--actor-email <email>]` **requires an explicit organization**. The organization must exist; nothing is guessed or created. Elevate is never created as a tenant.
- `mix nd_first.seed --dev` (dev/test only; raises otherwise) uses or creates the **"ND First Pilot — Development"** organization (slug `nd-first-pilot-dev`) plus demo users and memberships.
- Seeds are **idempotent and non-destructive**. An existing record matching the seed counts as "unchanged". An existing record that differs is reported as **drift and left untouched**.
- The workbook import loads the Spr '26 and Sum '26 seasonal ratings (36 values) as `ImplementationRating` observations with `source: :workbook_import`, `author_id: nil`, `measurement_date: nil`, `source_last_updated_on: 2026-08-18`, `recorded_at` = actual import time, and `recorded_by_id` = the `--actor-email` user if given. Re-runs skip existing entries. A conflicting value is reported, not overwritten.
- Callable in releases via `bin/emisint eval 'Emisint.Improvement.Seeds.run!(...)'`.

---

## Tasks

### Phase 1a: foundation (done)

- [x] **1.** Exclude only the two new reference files via `.git/info/exclude` (local, not `.gitignore`).
- [x] **2.** `Accounts.School` + `Accounts.SchoolMembership`: tenant resources, policies, and consistency validations.
- [x] **3.** `Emisint.Improvement` domain: `GoalPlan`, `Goal`, `Metric`, `ReportingPeriod`, `AnnualAssessmentGoal` (read-only definitions, derived scope, policies, 0–1 validation).
- [x] **4.** `ActualResult` + `ImplementationRating` (+ embedded `EvidenceLink`): observation/correction model, structural "current", unique indexes for concurrency, value states, provenance, policies.
- [x] **5.** Fort Yates seed data (4 goals, 18 metrics, 11 periods, PDF annual goals) + idempotent, drift-reporting loader + `mix nd_first.seed` (explicit org or `--dev`).
- [x] **6.** Workbook historical ratings import (Spr '26, Sum '26) as described above.
- [x] **12a.** Tests for 2–6: definitions, value states, corrections and concurrency, independence of actual and rating, cross-org and cross-school with forged IDs, system admin switching, seed counts, values and flags, idempotence, drift, and org requirement.

### Phase 1b: UI (done)

Routes (authenticated, `LiveScope` tenant): `/school-goals` (schools the user can read), `/school-goals/:slug?period=<code>` (dashboard), `/school-goals/:slug/metrics/:code` (history). Sidebar link: **School Goals**.

- [x] **7.** `Improvement.SchoolGoalsLive` dashboard. It has a seasonal period selector and four goal sections with all 18 metrics. Each metric shows its baseline and 18- and 36-month targets; unconfirmed 36-month targets are flagged with their source cell, and the review-heading flag is shown. The current actual and the current 0–3 rating are in separate columns, each with its own provenance. Missing values show "Not reported" / "Not rated". Ranges and suppressed values keep their shape, and suppression reasons are quoted verbatim. Annual ELA/math goals are in a separate "Proficient or Advanced" section. Seasonal category averages are labeled "not payment inputs".
- [x] **8.** Update panel, **revised:** the actual result and the rating have **independent forms and saves** (two separate entries, never one combined transaction), so saving one cannot touch the other.
  - Percentages are typed as 0–100 and normalized to 0–1 (`Improvement.Percent`).
  - Inputs: measurement date, notes, and up to 3 evidence links (http/https only).
  - Explanation-only "Unavailable" entries are allowed.
  - When a current entry exists, saving creates a correction that requires a reason. The corrected entry is fixed when the panel opens, so a concurrent correction is rejected with "already corrected by someone else".
  - The rubric labels are quoted from `Goals Dashboard!A15:A18`.
- [x] **9.** `Improvement.MetricHistoryLive`: every actual result and rating per period, with Original/Correction, Current/Superseded, the correction reason, workbook provenance ("Original author unknown", source cell, workbook date, import time and importer), and "Correct this" on current entries for contributors.
- [x] **10.** Access guard. Schools and metrics are loaded as the actor inside their tenant, so an unreadable school or metric redirects to `/school-goals` with "not found, or you don't have access". `Improvement.Access.can_contribute?/3` hides the controls, and every save is re-authorized by the resource policies. Forged `open_update`/`save_*` events from viewers are refused, and `?update=` URLs are ignored for viewers.
- [x] **11.** `Improvement.Payment.summary/2`: always "Awaiting review" with no amount. Category counts come from the plan's metrics, and cap and weights come from the plan. It takes no seasonal ratings or actuals as inputs.
- [x] **12b.** LiveView tests (`test/emisint_web/live/improvement/school_goals_live_test.exs`) plus `Percent`/`Payment` unit tests.

**Browser review follow-ups (done):**

- **Table fit:** baseline and both targets share one compact column, headers wrap, and Update/History sit in a sticky right column. In headless Chrome, at 1280×800 through 1536×864 there is no horizontal scrolling. At 1024 px and phone width the table scrolls, but all 36 action buttons stay in view.
- **Source details:** dashboard cells show a one-line source summary that expands into the full provenance (it stays open across LiveView updates). History still shows everything expanded.
- **Implementation steps:** each goal has an expandable panel with the planned count for every period. The step wording is **not in either source** (see unresolved item 16), so the panel says so and will link the plan document once `progress_doc_url` is set.

**Local demo** (`mix nd_first.seed --dev`; dev/test only, password `nd-first-dev-password`):

| Email | Role | Fort Yates access |
|---|---|---|
| `admin@example.com` | EMO admin | all schools in the dev org |
| `school@example.com` | School leader | contributor |
| `viewer@example.com` | School leader | viewer (read-only) |

These replaced the earlier `nd-first-*@example.com` addresses. The seed renames an earlier demo account in place (same id, password, memberships, sessions) instead of creating a new one. It never renames or merges when the new address belongs to another account; that case is reported as drift.

**Verification (2026-10-22):**

- ND First tests: 87/87 pass.
- Full suite: 279 tests, 157 failures. All 157 are the pre-existing legacy failures (an identical list on a clean HEAD checkout), and none are new.
- Migration drift:
  - `mix ash_postgres.generate_migrations --dev --dry-run` exits 0 with "No changes detected".
  - `mix ash.codegen --check` exits 1 both here and on clean HEAD, because the teammate's committed `20260701032125_migrate_resources1_dev.exs` and its `_dev.json` snapshots are ignored by non-dev codegen. That file was left untouched.

### Phase 2: public state data

- [x] **13.** Official downloads obtained and inspected (details below). Fixtures in `test/fixtures/nd_insights/`: real Fort Yates rows copied unchanged under their official file names, plus one clearly synthetic file (`…-2099-2100-v20990101.csv`, institutions `TEST00000x`) for suppression, duplicate and conflict cases.
- [x] **14.** New global domain `Emisint.NdInsights`, separate from the Michigan `Mde*` tables, with two resources:
  - `SourceFile`: one row per official file, with publication version, SHA-256 and the last import report.
  - `StateResult`: one row per published measure (long format, so growth and engagement measures keep their own names rather than performance-level columns). It keeps every source dimension and `raw_row`, an explicit `value_state` (`exact | range | suppressed`), `unit` (`proportion | level | percentile`), `natural_key` and `publication_version`.
  - Migration: `20261022153939_add_nd_insights_state_results`.
Task 15 is split. The CLI import is implemented; the upload screen and background job are **deferred and not done**.

- [x] **15a.** CLI import, implemented: `NdInsights.Parser` + `NdInsights.Importer` + `mix nd_insights.import --institution-id <id> FILE…`.
  - **Idempotent:** re-importing a file creates nothing.
  - **Republished files:** a newer state publication is stored alongside the older one, and differing values are reported as `changed_from_previous`.
  - **Conflicts:** a stored value that differs for the same publication is reported, not overwritten. A row repeated in one file with different values (one ID under two names) is reported, and none of it is imported.
  - **Name check:** the published name is compared with the Emisint school name. Matching is by InstitutionID only; a mismatch is reported and never used to link.
  - **Separation:** imports never touch `Improvement` entries.
- [ ] **15b.** Deferred, not started: an Oban worker, an upload card in `DataImportLive`, and an import-log type for ND files. Until these exist, imports run from the command line against local files and their reports are kept on `SourceFile.last_report`.
- [x] **16.** "Official state results (ND Insights)" section on the school dashboard.
  - **Filters:** academic year, assessment (Combined/Standard/Alternate) and student group. They live in the URL, independent of the seasonal period.
  - **Content:** achievement (Novice / Approaching Proficiency / Proficient / Advanced, then a separate derived "Proficient or Advanced" range and % tested), growth, Engagement Survey categories, survey participation (its own line, see item 23), source files with versions collapsed under "Data sources", and links to the Insights school page and Data page.
  - **Filter scope:** academic year applies to all sections; assessment type applies to achievement and % tested; student group applies to achievement and growth; the Engagement Survey is always all students. Each section states which filters it uses.
  - **In-page navigation:** Goals / Annual Targets / State Results jump links under the page header.
  - **Missing groups** show "Not published"; nothing is zero-filled or reduced to a midpoint.
  - **Annual goals** gain a "published · Proficient or Advanced (derived)" column. A comparison is made only when the year, Reading/Math, Combined (the goal includes the alternate assessment), All Grades, All students, All accommodations and the Proficient-or-Advanced measure all match. Every value is labeled **Derived** (the published Proficient and Advanced values added, with no adjustment).
  - **No assumed allowances.** Published values are never widened, narrowed or rounded; there is no documented basis for doing so. The statuses are:
    - **"Goal status pending range clarification":** at least one component is a published range. The derived range is shown, with no Meets/Below verdict, until the state documents what range endpoints mean (item 17).
    - **Meets goal / Below goal:** only when both components were published as exact values. Their sum is compared with the goal exactly as published.
    - **"Not derivable":** a component is suppressed.
    - **"Not yet published":** no matching row.
  - **Focused tests (`school_results_test.exs`, `state_results_components_test.exs`):**
    - **Real 2024-25 data:** Reading 20–39% gets no verdict for goals from 5% to 90%. Math 0–20% gets no verdict even for a 37% goal.
    - **Mixed components:** range+range, exact+range and range+exact are always pending.
    - **Exact components:** 30% + 5% = 35% → Meets at 35% and 34%, Below at 35.1% and 36%, with no allowance.
    - **Matching still required:** exact components in a different year, subgroup, grade, assessment type, accommodations, subject or dataset → "Not yet published". A goal that excludes the alternate assessment matches only Standard rows, and other measures are never compared.
    - **Display:** pending results show the derived range and no verdict; exact verdicts say they were compared as published.
  - **Not compared:** workbook metrics, because their year, grade and growth-category coverage is not stated.
  - **Payment card:** still "Awaiting review".

**Source verification (2026-10-22):**

- **Downloads:** 17 CSVs from https://insights.nd.gov/Data, obtained through the page's own Download controls in a browser session. They're saved in `references/nd_insights/` (excluded with `.git/info/exclude`), with `source_manifest.json` recording URLs, download time, SHA-256, publication version and the embedded data dictionaries.
  - Assessment Performance, Participation and Growth Rate: 2021-22 through 2024-25.
  - Engagement Survey: the five "All Students" files, each covering 2017-18 through 2024-25.
- **Data dictionaries** are embedded on the Data page (no separate file). They list column names, mostly "No Description Available"; only Engagement has descriptions.
- **Identity:** InstitutionID `4300429212` is "Fort Yates Middle School" in every file. The Engagement files give its district as "Ft Yates Public School District".
- **"Partially" = "Approaching Proficiency":** confirmed from the live page's chart data, not inferred from order. For 2024-25 Combined, All Grades, the school series named "Approaching Proficiency" starts at the CSV's `PartiallyRangeLow` in ELA (30), Math (10) and Science (20), and is distinct from Novice, Proficient and Advanced. (The plan earlier said "Approaching Proficient"; the website label is "Approaching Proficiency".)
- **Assessment types:** Combined = `Comp`, Standard = `Reg`, Alternate = `Alt`. This is confirmed from the State column, where Combined ELA "Approaching Proficiency" is 42 and matches `Comp` 0.42, and Standard is 43 and matches `Reg` 0.43. For Fort Yates, `Comp` and `Reg` rows are identical (no alternate-assessment group was published).
- **Subjects and grades:** Performance and Participation use `Reading`, `Math` and `Science`; Growth uses `ELA` and `Math` (shown as ELA). Fort Yates grades published are All Grades, 6, 7 and 8; grade 5 never appears although the website offers it.
- **Subgroups published for Fort Yates:** All, Female, Male, Homeless and Non-Homeless.
- **Value format:**
  - Proportions are 0–1, written as `RangeLow`/`RangeHigh` pairs: 10-point bins (e.g. 0.3–0.39), open-ended ranges (0–0.2, 0.8–1, 0–0.1) and, in 2022-23, 5-point bins.
  - low = high is an exact value; this occurs statewide, for example at state level.
  - Engagement cells are text ranges such as `"0.30-0.34"`.
  - Growth `OverallGrowthLevel` is an ordinal level and `OverallGrowthPercentile` is a number.
- **Suppression:**
  - Performance and Participation files contain no `*` and no empty cells. Unpublished groups are simply absent, and the website shows "No Data Available" for them.
  - Growth and Engagement files contain empty cells, which are stored as `suppressed` per the Data page's statement ("an asterisk (*) or an empty cell is shown").
  - The school page also states: "To protect student privacy, data for populations with less than 10 students will not be displayed." This is quoted as context and is never assigned to individual rows.
- **Dev import:** 1,156 Fort Yates measures from 17 files on the first run and 0 created / 1,156 unchanged on the second. There were 0 conflicts, 0 parse errors and 0 name mismatches.

**What was verified, and against what (2026-10-22).** Two separate checks. Evidence, including scripts and per-value results, is in `references/nd_insights/verification/` (git-ignored).

- **Check A, database vs CSV (import fidelity):**
  - An independent Python re-parse of all 17 official CSVs, compared with every Fort Yates row in the dev database.
  - 1,156 / 1,156 measures match on value state, lower bound and upper bound (or exact value), with 0 missing and 0 extra.
  - By dataset: Performance 592, Participation 192, Growth 252 (168 level ranges + 84 overall levels and percentiles), and Engagement 5 × 24.
  - All years in the files are covered: 2021-22 to 2024-25, and Engagement 2017-18 to 2024-25.
- **Check B, website vs CSV (meaning and labels):**
  - The visible value labels were read from the live Insights charts. Each label is bound by d3 to its level and its State/District/School position, so nothing depends on screen order. They were compared with the CSV for the **School** position under every filter the page offers, with 0 mismatches.

    | Dataset (Insights page) | Both bounds or exact value match | Lower bound only | Unpublished on both |
    |---|---|---|---|
    | Performance Overview (2022-23 to 2024-25 × Combined/Standard × All/5/6/7/8 × ELA/Math/Science × 4 levels) | 115 | 109 | 136 |
    | Participation Overview (same years, types and grades × 3 subjects) | 68 | — | 4 |
    | Growth by level (2022-23 to 2024-25 × ELA/Math × All/7/8 × All/Female/Male/Homeless × 4 levels) | 56 | 56 | 176 |
    | Overall growth level and percentile (both data types × ELA/Math × All/7/8 × 4 groups, every year on the chart) | 56 exact | — | — |
    | Engagement comparison (2020-21 to 2024-25 × Overall/Behavioral/Cognitive/Emotional × 3 levels) | 60 | — | — |

    "Lower bound only" means the site draws no label on that bar segment, so the upper bound can't be read from the page; the lower bound was checked from the bar's bound value instead.
  - Because Check A shows the database equals the CSV, Check B also covers the database values for those cells.
- **Not verified against the website:**
  - **Years the site doesn't offer:** 2021-22 performance, participation and growth (the site shows three years); Engagement 2017-18 to 2019-20.
  - **Groups and tabs:** the Alternate assessment (Fort Yates publishes no alternate group); Performance and Participation student groups (the Demographics tabs); the Engagement "Participation" tab and its file.
  - **Upper bounds on unlabeled segments:** the 109 performance and 56 growth values marked lower-bound-only.
  - **Our dashboard's derived "Proficient or Advanced":** it has no counterpart on the site.
- **Superseded:** the earlier "224 of 224" check compared only the bar values (lower bounds) for Performance. It is replaced by Check B.

**Phase 2 verification:**

- ND First tests: 131/131 pass, run before the final change. After the allowances were removed, the affected tests (`test/emisint/nd_insights`, `test/emisint_web/live/improvement`) pass 65/65. The full suite was not re-run after that change.
- Full suite: 323 tests, 166 pass. The 157 failures are the same legacy failures as clean HEAD, with none new.
- In headless Chrome on the dev server: no horizontal overflow at 1280, 1440 or 390 px, and the year switch re-renders without changing the seasonal period.

### Phase 3: 18-month review + payment

- [ ] **17.** `ReviewRating` (same entry model, `:reviewer` policy).
- [ ] **18.** Review entry UI, separate from seasonal updates.
- [ ] **19.** Live payment card: Awaiting review → Provisional → Complete.

### Phase 4: expansion

- [ ] **20.** Resolve open items, then seed the other seven schools.
- [ ] **21.** `PortfolioLive` (`/nd-first`).
- [ ] **22.** Optional Typst PDF export.

---

## Unresolved items (recorded, not guessed)

1. **`Ft Yates Goals!P7` = 90 and `P16` = 80** (G1-M4 and G2-M4 36-month targets), in `General` format while other targets are decimals. The originals are kept in `source_values`, `target_36m` is left **unset**, and the metrics are flagged `:target_36m_needs_confirmation`. They are excluded from calculations.
2. **Goal 4 column I is headed "Target Check"** (`I26`), while Goals 1–3 use "18-Month Review Rating" (`I3`, `I12`, `I19`). The payment sheet averages the whole of `'Ft Yates Goals'!I:I` by the category in column A (`Performance-Based Payment!C4`, `E4`), so Goal 4's rows 27–30 would count. (Correction: an earlier revision said the formula reads `I27:I30` directly; it uses whole-column `AVERAGEIF`.) The dashboard shows this as one expandable note under the Goal 4 heading; the metrics keep `:review_18m_column_heading_unconfirmed`.
3. **Column Q "Target Check"** (36-month) has 3/2/1/0/N/A validation with an undefined meaning.
4. **Review dates and reviewer assignments** are unknown.
5. **Solen vs Cannon Ball:** PDF p.4 reads "Cannon Ball Elementary School, Solen Public School District". Unconfirmed; deferred to Phase 4.
6. **Weight labels conflict:** "Goals Dashboard" `T2`/`V2` label Systems 30% and Outcomes 70%. The payment sheet (and our working rule) use Systems 70% and Outcomes 30%. This is a source-document issue to resolve with the program owner.
7. The workbook hides a $0 payout as blank. We will show $0.00.
8. Payout rounding is not specified.
9. The average-score color key (`W5:X8`) has a 0.49–0.50 gap. No color bands until confirmed.
10. **Production owning organization:** to be supplied explicitly at seed time.
11. Baseline years and sources for the workbook metrics are unknown. Workbook "Proficient" ≠ PDF "Proficient or Advanced".
12. ~~Insights CSV verification and the Growth Rate / Engagement Survey schemas are pending (Task 13).~~ Done; see Phase 2. Open source questions are items 17–26.
13. **Teammate dev migration:** `mix ash.codegen --check` fails until the owner of `20260701032125_migrate_resources1_dev.exs` (SSS feature) converts it with a named `mix ash.codegen`. Running that command elsewhere would fold their migration into someone else's.
14. **Stale `schools` snapshots:** `priv/resource_snapshots/repo/schools/20260225234912.json` and `20260317014725.json` describe the old table dropped by `cleanup_removed_resources`. The new snapshot supersedes them, but they could be removed in a dedicated cleanup.
15. Timestamps are displayed in UTC. The app's per-session timezone cookie is not used yet.
16. **Implementation step wording is missing from the sources.**
    - The workbook stores only the step counts per period (`Ft Yates Goals!D2` and the following columns). `C1` points to "the linked action-planning and progress-monitoring document", whose link (`B1`) is "TBD".
    - The Evidence Tracker has no Fort Yates rows.
    - PDF p.17 lists "Supporting Academic Initiatives" for the annual goals, not per-period steps for the four workbook goals.
    - To show step text, we need that document (or its URL for `GoalPlan.progress_doc_url`).
    - Related: the workbook has threaded reviewer comments on the Sum '26 goal headers (`F3`, `F12`, `F19`, `F26`). These are not imported.

**ND Insights source questions (Phase 2):**

17. **Range endpoints:** does `0.29` mean "up to 29%" or "below 30%"? Are values rounded before binning? The website shows "20% to 29%". Until ND DPI documents this, any goal comparison that involves a published range shows "Goal status pending range clarification" with no verdict. No adjustment is assumed. Every Fort Yates achievement value published so far is a range, so all Fort Yates goal comparisons will be pending until this is resolved. When it is, `NdInsights.SchoolResults.compare_goal/2` is the single place to apply the documented rule.
18. **Open-ended range widths** (0–10%, 0–20%, 0–40%, 80–100%) vary by group with no documented rule, which makes many derived ranges wide (e.g. 0%–40%).
19. **Why grade 5 is never published for Fort Yates** (suppressed, or no tested students) is not stated.
20. **The test changed:** Insights says the achievement test was ND A+ in 2024-25 and NDSA in 2022-23 and 2023-24. Comparability across that change is unconfirmed, so year-over-year comparisons should be labeled before any trend charts are added.
21. **No annual goal year has published data yet:** the PDF goals start in 2025-26 and the latest file is 2024-25, so every goal currently shows "Not yet published". The 2025-26 download needs to be imported when Insights publishes it.
22. **Growth mapping unconfirmed:** whether the workbook's "met state growth expectations" (G2-M3, G3-M3) means Insights "Meets", or "Meets + Exceeds", for which grades and year, is unknown, so no comparison is made.
23. **Engagement mapping unconfirmed:** the workbook's G4 disengagement metrics plausibly correspond to the Engagement Survey "Disengaged" level by area, but the baseline year and survey grades are unstated, so no comparison is made.
    - **Engagement Participation, resolved:** the file's data dictionary describes its year columns as "percent of participants that fall into this engagement level", but the data contradicts that. The Committed, Compliant and Disengaged rows are identical for all 5,656 institution-years statewide (the state row reads 0.89 for each level), and Insights' Participation tab shows it as "Overall Participation — participation of the enrolled student body in the engagement survey", one series per year.
    - The live School values (87, 92, 92, 92, 97.5 for 2020-21 to 2024-25) are the midpoints of the CSV ranges, and the State values equal the CSV's exact state values.
    - The dashboard therefore shows it as **survey participation**, separate from the engagement categories. It is shown as a range, never a midpoint, and as a single value only when every published row agrees; otherwise each row is listed. All three source rows remain separate records.
24. **The data dictionaries are mostly empty** ("No Description Available"). The Comp/Reg/Alt and Partially meanings above come from the website, not the dictionary.
25. **The Insights website draws participation ranges at their midpoints** (e.g. 97.5 for 95–100%). Emisint does not; it shows the published range.
26. **Statewide duplicate InstitutionIDs:** some institutions appear under two names, or two schools share one ID, with different values (e.g. "Hope Page 85" / "Hope-Page 85"; "Badlands Elementary" / "Watford City Elementary"). These are treated as conflicts. None affect Fort Yates, but portfolio expansion will need a rule for them.

## Risks and dependencies

- Tasks 3–6 depend on 2. Tasks 7–11 depend on 3–6. Task 19 depends on 17. Task 16 depends on 13–15.
- These are the first tenant-scoped resources, so org-switching and forged-tenant tests are mandatory.
- **Orphaned tests:** `test/emisint/accounts/school_test.exs` was written for an older, Michigan-shaped `Accounts.School` (MDE codes, update action, `Registry.Enrollment`). It already fails (the module didn't exist) and will keep failing against the new resource. It is left untouched pending your decision. The same applies to the orphaned registry, compliance, analytics, and worker tests.
- Definitions are read-only. Changing a baseline, target, or weight later requires a versioned definition (`definition_version`) or an audited update (e.g. AshPaperTrail with `attributes_as_attributes [:organization_id]`), not an in-place edit.
- The repository lives in an iCloud-synced Desktop folder. Evicted files once made `git status` fail and recursive `grep` hang; the folder is currently set to "Keep Downloaded".
- Insights downloads aren't scriptable with curl (ASP.NET postback). They were obtained with a headless browser using the page's own controls. Future updates need the same, or a manual browser download into `references/nd_insights/`, followed by `mix nd_insights.import --institution-id 4300429212 references/nd_insights/*.csv`.
