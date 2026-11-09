# Plan: ND First School Goals Dashboard (Fort Yates pilot)

_Revision 4: Phase 1 (tasks 1–12) and Phase 2 (tasks 13–16, ND Insights import and display for Fort Yates) are implemented and tested. Phase 3 onward has not started._

## Approach

Add a new, state-agnostic **school improvement goals** feature: school → goal plan → goals → metrics → reporting periods. Values are stored as **append-only entries**. Fort Yates Middle School is seeded from a hand-transcribed data module (not the workbook itself). The other seven ND First schools reuse the same structures later with only new seed data.

Three kinds of numbers live in **separate resources** and are never derived from each other:

| Kind | Resource | Scale | Used for |
|---|---|---|---|
| Actual metric result | `ActualResult` | metric unit; percent normalized to 0–1 | display vs baseline/targets |
| Seasonal implementation rating | `ImplementationRating` | 0–3, N/A, or unavailable | seasonal averages |
| Formal review rating | `ImplementationRating` via `:record_review` (18-/36-month review periods only) | 0–3, N/A, or unavailable | estimated payment only |

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
- **Formal review ratings** (November 1, 2026) use the same `ImplementationRating` entry model through `:record_review`, which accepts only `:review_18m` / `:review_36m` periods (`:record` accepts only seasonal ones). Same contributor permissions, validation and correction history as seasonal ratings; entered separately from actual results.
- **`PaymentEstimate`** (November 1, 2026): an append-only recorded estimate for one checkpoint, computed on the server, with every assumption it used (see Payment).

### Payment (`Improvement.Payment`)

**Provisional rule (November 1, 2026).** Ram authorized using a best-estimate payment rule until the actual terms are confirmed. He did **not** specify the cap or split: the $70,000 total and the equal $35,000 split below are **our selected provisional assumptions**, and they are **not confirmed contract terms**. Every amount is labeled "Estimated payment — provisional cap and split" and the terms sentence says so.

- **Cap and split (our selected assumptions):** $70,000 total per school across both checkpoints; $35,000 to the 18-month review and $35,000 to the 36-month review. Stored on `GoalPlan` (`payment_cap`, `allocation_18m`, `allocation_36m`, `payment_terms_status: :provisional`, `payment_terms_note`, `payment_terms_version`), set only through the system-only `:set_payment_terms` action, which validates that the allocations sum to the cap and bumps the version on any change. Fort Yates only; Oberon and Valley Middle stay "Payment terms are not set".
- **Weights (confirmed October 23, 2026):** 18-month review 70% Systems / 30% Student Outcomes; 36-month review 30% Systems / 70% Student Outcomes.
- **Formula:** the workbook's own mapping ('Performance-Based Payment' C–I: category `AVERAGEIF`s, weighted sum, ÷ 3, × amount), with the checkpoint allocation in place of the workbook's single $70,000:
  `estimated payment = checkpoint allocation × (Systems average × Systems weight + Student Outcome average × Student Outcome weight) ÷ 3`.
  Category averages are exact and taken separately before weighting; the result is capped at the allocation and rounded half up to cents.
- **Inputs:** current formal review ratings in the checkpoint's review period only. Seasonal ratings, target values and actual results are never inputs.
- **Completeness:** every plan metric needs a scored review rating; an explicit 0 counts. A missing, N/A or unavailable rating leaves the checkpoint "Awaiting review" (never $0). Nothing is excluded and the weights are never renormalized. (This deliberately differs from the workbook's `AVERAGEIF`, which skips blanks and hides $0.)
- **Display:** per checkpoint, category averages, weights, weighted score, allocation and estimate. The combined total appears only when both checkpoints are complete; otherwise a "Subtotal … (18-month review only)" line. Same wording on the dashboard and in the PDF.
- **Recorded estimates:** org admins can record an estimate for a complete checkpoint (`PaymentEstimate`). It stores the amount, cap, allocation, weights, maximum rating, averages, weighted score, terms status/version/note, label, formula and each rating (id, score), so a later terms change never rewrites it. Estimates are separate from actual payments; Emisint records no actual payment.
- **Goal 4 (item 2) is not resolved by this:** the formula averages every metric in the category, so a complete checkpoint still needs review ratings for G4-M1–G4-M4.

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

### October 23 meeting requirements (Fort Yates only; scope corrected October 27)

**Scope:** this phase covers **Fort Yates Middle School only**. The importer stays reusable (statewide files, schools selected by verified InstitutionID), but only Fort Yates data is imported. Expansion to the other seven schools is **deferred until the Fort Yates experience has been reviewed and approved** (Phase 4).

**Pilot-school configuration:**
- **The setting:** `config :emisint, :nd_first, pilot_institution_ids: ["4300429212"]` in `config/config.exs`, read by `Emisint.Improvement.Pilot`. With no setting, no school is included (fail closed).
- **Where it applies:**
  - **Landing page:** `/school-goals` lists only pilot schools (`Dashboard.list_schools(scope, institution_ids: Pilot.institution_ids())`).
  - **Import preview:** the upload preview offers only pilot schools (`UploadPreview.build(path, name, institution_ids: …)`) and says so (`#nd-pilot-scope`).
  - **Import (server):** the `import` event also drops any selected ID that isn't a pilot school, so a forged selection can't import another registered school.
- **What stays reusable:** `Dashboard.list_schools/1`, `UploadPreview.build/2`, `Importer` and `mix nd_insights.import` take any verified InstitutionID. Expansion means adding IDs to the setting (and seeding the schools), not code changes.
- **Not hidden:** a non-pilot school's dashboard and PDF URLs still open for users with access, since the records are kept. Only the listing and the import UI are limited.
- **Seeds:** `Seeds.schools/0` (the default for `mix nd_first.seed`) is `[FortYates]`. `Seeds.available_schools/0` lists every verified module, including Oberon and Valley; they are seeded only when passed explicitly as `schools:`.

- [x] **M1. ND Insights CSV upload (system admins)**, at `/admin/import/nd-insights` (linked from Data Import and the ND First landing page). Drag-and-drop upload of the official Assessment Performance, Assessment Participation, Growth Rate and Engagement Survey CSVs, statewide with their original headers. It reuses `NdInsights.Parser` and `Importer`.
  - **Preview first** (`NdInsights.UploadPreview`): validation errors, detected dataset, years and publication version; whether the exact file was imported before; whether it revises an already-stored publication; and the registered ND schools found in the file, matched by InstitutionID, each selected explicitly. IDs not in the server-side preview are ignored. Nothing is hardcoded.
  - **Commit:** every attempt writes an `NdInsights.ImportRun` (user, time, file, SHA-256, publication version, selected institutions, outcome `imported`/`no_changes`/`rejected`/`failed`, report). Repeat uploads create nothing. A revised publication needs explicit confirmation and is stored beside the older one.
  - **Afterwards:** open dashboards refresh via PubSub (`"nd_insights"`). Authorization is server-side, `system_admin` only, checked on mount and on every event.
  - **Still deferred:** the Oban job (15b). The import runs as a LiveView async task. `mix nd_insights.import` has no flag for accepting revisions; use the UI for revised publications.
- [x] **M2. Performance colors.**
  - **What gets colored:** subtle DaisyUI `badge-soft` / dot markers (light and dark), always beside the text label. Only documented goal comparisons (Meets/Below, exact values only), the workbook rubric (0–3) and the official Insights level categories (as column markers) are colored.
  - **What stays neutral:** published ranges, suppressed, missing, unconfirmed and pending results, each with an explanation (`#state-color-key`).
  - **Empty states:** explicit per filter combination for achievement, growth and engagement (e.g. Alternate: "Try Combined or Standard").
- [x] **M3. Individual-school PDF** (`/school-goals/:slug/report.pdf`, Typst via Imprintor, `priv/typst/school/nd_first_school.typ`).
  - **Content:** goals, metrics, baselines and targets, the selected period's actuals and ratings, annual targets with the dashboard's comparison statuses, state results for the selected filters, and the payment checkpoints (no payout). Values are formatted by the shared `Improvement.Display`.
  - **Report metadata:** period, filters, generation time (UTC), generated by, source files and notes.
  - **Layout:** US Letter, repeated table headers, unbreakable rows, goal headings kept with their tables, running header and page footer.
  - **Access:** the school read policy is enforced in the controller (signed out → sign in; no access → redirect with a flash).
- [x] **M4. Navigation.** "School Goals" is now **"ND First"** in the sidebar and on the landing page, with a factual introduction citing the ND DPI ND First page and the existing tiles. (URLs remain `/school-goals`.)
- [x] **M4b. Expansion to the other schools:** Oberon (November 4, 2026), then Valley Middle, Drayton, Dunseith, Mandaree and Warwick (November 8, 2026), all pending individual review; Cannon Ball deferred. See "Expansion: remaining participants".
- [x] **M5. Payment weights.** Per checkpoint: 18-month review = 70% Systems / 30% Student Outcomes; 36-month review = 30% Systems / 70% Student Outcomes (`Improvement.Payment`). How the $70,000 maximum applies across checkpoints is awaiting clarification, so there's no payout and no per-checkpoint cap, and Phase 3 stays open. *(Superseded November 1, 2026: Ram authorized a best-estimate rule, and we selected a provisional cap and split; see "Provisional payment rule".)*
- **Later phase:** the company-wide KPI dashboard.

**Verification (October 27):**
- **Fort Yates in headless Chrome:**
  - Re-uploading the statewide 2024-25 Growth Rate file previewed Fort Yates with 84 measures, all already stored. Importing created 0 records and logged a "No changes" run under `sysadmin@example.com`.
  - Colors were checked in both themes, the Alternate empty state appeared, and there was no horizontal overflow.
  - The PDF returned 200 for the admin and for `viewer@example.com`. The viewer is redirected away from the importer.
- **Automated:** the create-and-refresh path (144 new records, open dashboard updated) and the revision confirmation are covered by LiveView tests with Fort Yates fixtures.
- **PDF samples** (Sum '26 Combined 2024-25; Spr '26 Alternate 2023-24) were generated through the real route and inspected page by page. Each is 4 pages, with headers repeating, no split rows, subheads kept with their tables, and the Alternate empty state shown.
- **Tests:** ND First suites 173/173 pass (176/176 after the pilot-school configuration). Full suite 208/365: all 157 failures are the legacy orphaned suites listed under Risks (same count as clean HEAD), with none in ND First files.
- **Checks:** migration drift is clean (`ash_postgres.generate_migrations --dev --dry-run --check`). Every changed file passes `mix format --check-formatted` except `data_import_live.ex`, whose unformatted lines (≈3010–3032) predate this work.

**Expansion work started before the scope correction (kept, inactive pending review; nothing deleted):**
- **Code:**
  - `Improvement.Seeds.Oberon` and `Seeds.ValleyMiddle` (generated from their workbook sheets), listed in `Seeds.available_schools/0` but not seeded by default.
  - `Improvement.Workbook` payment rows for every sheet.
  - Tests: `test/emisint_web/live/improvement/additional_schools_live_test.exs` and the "additional ND First schools" block in `seeds_test.exs`.
- **Shared and kept for Fort Yates:**
  - The data-driven 18-month column note (`Workbook`).
  - `Display` and the `:text` unit / `value_as_text` / `source_value_is_date` metric flags (unused by Fort Yates; harmless).
  - The `schools:` option on seeds and fixtures.
  - The `sysadmin@example.com` demo user.
- **Dev database only (kept; hidden from the landing page and import UI by the pilot setting):**
  - Oberon Elementary (0301662261) and Valley Middle School (1800189752), each with a plan, goals (4 and 7), metrics (21 and 26), ratings (42 and 52) and annual goals (12 each).
  - 48 + 1,080 Insights results.
  - Two import runs.
  - No source file is used only by them, and the Fort Yates records are unaffected.
- **Verified mappings and open questions (for Phase 4):**
  - Cannon Ball, Drayton, Dunseith, Mandaree and Warwick workbook sheets are district- or multi-building-scoped, while the PDF and Insights data are per building. They need a modeling decision.
  - Oberon's grade band and historical annual goals are unresolved.
  - Valley's Measure 1 and English Learner targets were not stored.

### Color coding: school targets first (November 1, Fort Yates)

The primary status shows whether Fort Yates meets its own targets and documented expectations. State comparisons are optional context.

- **Implementation ratings:** the documented 0–3 rubric (Goals Dashboard!A15:A18): 0 Not Started red, 1 Some Progress amber, 2 Implementation on Track blue, 3 Demonstrated Progress green, each with its label. The badges use the accessible text classes.
- **Goal results** (`Improvement.GoalStatus`, shared by the dashboard and PDF):
  - **Shown together:** result, applicable target and status.
  - **Which target applies:** the reporting period's `kind` decides: the 18-month target at the 18-Month Review, the 36-month target at the 36-Month Review. Seasonal periods have **no target due**; no interim targets or trajectories are derived.
  - **Statuses:** Meets target (green) or Below target (red), respecting `direction` (`lower_is_better` meets at or below).
  - **Neutral, with a reason:** not reported; no target due; a result that isn't exact; a target that isn't a confirmed number (flagged for confirmation, workbook text or an Excel date).
  - **Today:** (updated October 31, 2026: the 18- and 36-month reviews are now selectable for actual results, see the growth-percentile section.) No actual results have been recorded. Every real metric is "Not reported", and a seasonal result would show "No target due this period". The Meets/Below path is covered by synthetic tests.
- **Annual targets:** unchanged. Matched to year, subject, Combined assessment, all grades, all students and Proficient-or-Advanced. Meets/Below only for exact published values; ranges show "Goal status pending range clarification". Every Fort Yates target year (2025-26 onward) is "Not yet published".
- **Published state results** (achievement, growth, engagement): **superseded October 31, 2026** — then colored by comparison with North Dakota (see "ND Insights color coding"). **Superseded again November 1, 2026:** the main tables now show school-goal status, and North Dakota appears only in its own section (see "State results colored by school goals"). Still true: no confirmed school target applies to them:
  - Workbook "Proficient" metrics differ from Insights levels (item 11).
  - "Met state growth expectations" isn't mapped (item 22).
  - Disengagement metrics aren't mapped (item 23).
  - `OverallGrowthLevel` numbers have no documented classification.
- **North Dakota comparison:** kept, in a collapsed "North Dakota comparison" area (`#nd-comparison`) listing only rated measures with this school's value, the state value and the comparison. The default PDF leaves it out; "Export PDF including the North Dakota comparison" (`nd_comparison=1`) adds it as an optional section. Published state results and benchmark rows are unchanged.
- **Waiting on results or a decision:**
  1. Results recorded at the 18- and 36-month reviews (Phase 3 review entry, plus review dates).
  2. Confirmed targets for G1-M4 and G2-M4 (36-month, cells P7 and P16).
  3. Mapping workbook metrics to Insights measures (items 11, 22, 23).
  4. A documented meaning for `OverallGrowthLevel`.
  5. The 2025-26 Insights download, for the annual targets.

### Growth-percentile decision and review checkpoints (October 31, 2026, Fort Yates)

- **Decision (October 31, 2026):** Ram says the growth baselines refer to growth percentiles, and this is accepted as the project decision. G2-M3 (ELA) and G3-M3 (Math) are **Overall Growth Percentiles**, not "the percentage of students meeting growth expectations". This resolves item 22.
- **Definitions** (`Improvement.GrowthPercentile`, used by the seed):
  - The numbers are kept and read as percentiles: ELA baseline 38, 18-month 43, 36-month 51; Math 41, 46, 52.
  - The source cells (`Ft Yates Goals!D/H/P15` and `D/H/P22`) are percent-formatted proportions (0.38).
  - Metric fields: `unit: :percentile`, `performance_measure: :growth_percentile`, description "Overall growth percentile (ELA / Math)", shown with no percent sign.
  - **Provenance:** the raw cells stay in `source_values`, with the workbook wording "Percentage of students met state growth expectations" (`source_values["description"]`) and the dated decision (`source_values["unit_decision"]`).
- **Existing databases:**
  - `GrowthPercentile.run/2`, called by `Seeds.run/2` before seeding Fort Yates, converts the two metrics to exactly the fresh-seed record (`Metric :apply_unit_decision`, system only).
  - It is repeat-safe. A metric matching neither the old nor the new definition is reported as drift and left untouched. Oberon and Valley G2-M3/G3-M3 are untouched.
  - Current actual results entered as percentages are restated by an appended `:convert_unit` correction with the same number (0.45 → 45). The original entry and author are kept, and History shows the original "Entered as %".
  - Dev had no actual results; the conversion ran on the dev seed (see verification steps).
- **ND Insights mapping:**
  - **Measure:** Growth Rate `OverallGrowthPercentile`, subject ELA or Math, the published **All Grades** row, all students.
  - **Not used:** Meets, Meets + Exceeds, `OverallGrowthLevel`, or an average of grade rows.
  - **Dashboard and PDF:** the mapping is shown with the latest published year as reference only (2024-25: ELA 38, Math 41, the same as the baselines).
- **Review checkpoints:**
  - The period selector now includes the 18-Month Review and 36-Month Review, for viewing and entering **actual results** with the existing contributor permissions and the append-only history.
  - Review ratings (payment scoring) are still not recorded. The rating form is hidden at reviews, `ImplementationRating` still rejects review periods, and payment stays "Awaiting review".
  - Review dates are not set (item 4).
- **Published value as a review result** (`ActualResult :record_published` / `:correct_published`):
  - Growth-percentile metrics, at a review only.
  - **Reference only by default:** every published year is listed and none is preselected.
  - **Explicit year and intentional save:** a value becomes a review result only when a contributor explicitly chooses its school year, sees a preview ("Saving records 38 as the 18-Month Review result · Source year 2024-2025 …"), and saves.
  - **Nothing automatic:** no review result is filled from the baseline or the latest available year.
  - **No year rule (corrected October 31, 2026):** which assessment years are eligible for each checkpoint has **not been established**, so no year is preferred or refused. The earlier draft's 2025-26 cutoff, inferred from Spr '26, was removed. The only refusals are a missing year and a year with no published row.
  - **Context:** 2024-25 holds the same values as the workbook baselines (38 and 41), and the preview shows the baseline beside the chosen value.
  - **Provenance:** `source: :nd_insights`; `source_ref` keeps year, population, measure, publication version and file. The source year is shown with the result on the dashboard ("ND Insights · source year …") and in the PDF.
  - Never copied into seasonal periods.
- **Status:**
  - Unchanged `GoalStatus` rules: Meets target (green) at or above the target due for higher-is-better metrics, at or below it for lower-is-better metrics; equality meets. Seasonal periods have no target due.
  - Unconfirmed targets (G1-M4 and G2-M4, 36-month) and missing results stay neutral. At a review, a missing result reads "Not compared: no result reported".
- **Unchanged:** 0–3 rating badges, annual achievement comparisons, the collapsed North Dakota comparison, the engagement mapping (item 23), and payment.

### Compared with North Dakota (October 31, Fort Yates)

- **Benchmark data:**
  - **What it is:** the official "State of North Dakota" rows (InstitutionID 99999, `NdInsights.Benchmark`), verified in every 2021-22 to 2024-25 Assessment Performance, Assessment Participation and Growth Rate download and in the Engagement Survey downloads.
  - **How it imports:** with the selected school through the existing importer. The preview (`#nd-benchmark`) and the result (`#nd-result-split`) show the state rows separately, and the import history labels them "ND state benchmark".
  - **Restrictions:** the server adds them only when the file names them "State of North Dakota", and never without a selected pilot school. There's no school record or tile for 99999.
  - **School-only files** still import, with a note that the file has no state rows.
  - **Dev:** all 17 reference files were re-uploaded on the Fort Yates import page. That added 35,070 state measures, and every Fort Yates measure was reported as already stored (no duplicates).
- **Matching** (`NdInsights.StateComparison`):
  - Year, dataset, subject, grade, assessment type, student group, accommodations and measure must all match; nothing is substituted.
  - **All Grades** is compared only when both sides publish the same grades. For Fort Yates it's always context only (6–8 or 7–8, against 3–8 and 10 statewide).
  - **Engagement Survey** downloads have no grade breakdown, so they're always context only.
- **Direction:**
  - **Favorable:** lower Novice, Does not meet and Disengaged; higher Advanced, Proficient or Advanced (derived), Exceeds, Meets or Exceeds (derived, a new growth column) and Committed.
  - **Not rated:** intermediate levels (Approaching Proficiency, Proficient alone, Approaches, Meets, Compliant), % tested, survey participation, and the overall growth level and percentile.
- **Ranges (corrected November 1): not compared.** **Superseded October 31, 2026** by "ND Insights color coding" below: ranges are now compared through their published bounds (no tolerance or allowance), as a comparison of published values. The removed "widest interval" assumption stays removed.
- **Display:** see "ND Insights color coding" below (result cells colored directly, legend, per-cell reason; the PDF uses the same module).
- **Documentation that would tighten range comparisons** (still unanswered; the current rule is conservative without it; from ND DPI, e.g. the Insights team at dpidashboard@nd.gov; written methodology, not inferred from the data):
  - **Rounding:** how percentages are calculated and whether they're rounded or truncated, and to what precision, before a range is assigned, and whether exact values are rounded.
  - **Endpoints:** whether both endpoints are inclusive, i.e. whether "20%–29%" covers every value from 20% up to but not including 30%.
  - **Overlaps:** why bins overlap at shared endpoints (e.g. "0%–10%" and "10%–19%").
  - **Bin widths:** how widths are chosen (5, 10, 20, 40 points; open-ended 0–10% and 80–100%) and whether any noise or other perturbation is applied.
  - **State values:** whether exact state values carry the same rounding.
- **Open source questions:**
  1. The range construction rules above.
  2. The grade coverage of the Engagement Survey.
  3. Whether All Grades comparisons with a different grade span are acceptable.
  4. Whether % tested or the growth level/percentile have an agreed interpretation.

### ND Insights color coding (October 31, 2026, Fort Yates; revised the same day)

**Superseded November 1, 2026 for the main tables** (see "State results colored by school goals"): North Dakota colors, labels, the legend, coverage notes and the Engagement benchmark note now appear only in the collapsed "North Dakota comparison" section and in the optional comparison PDF. Everything below still describes that section.

**Done:** the Achievement, Growth and Engagement result cells and the North Dakota comparison table are colored directly, on the dashboard and in the PDF. Both use one shared module: `NdInsights.StateComparison` (status, short label, full label, explanation, tone, legend text, section notes) and `NdInsights.SurveyBenchmark` (the Engagement benchmark and its compatibility check). Published values and ranges stay visible as published.

**Three kinds of comparison, never mixed, and none is a school goal status:**
- **State benchmark** ("vs ND"): Achievement and Growth against the matching "State of North Dakota" row.
- **Middle-school survey benchmark** ("vs ND gr. 6–8"): Engagement against the same year's statewide middle-school counts, only when verified (see below).
- **Participation target** ("95% target"): % tested.

School goals stay in the goal tables (`GoalStatus`) and Annual Targets (`compare_goal`).

**Comparison of published values** (the revision removed the earlier ±1 percentage-point allowance, which was a design choice, not a state rule):
- A range is compared through its published low and high values, never a midpoint. An exact value is compared as published.
- **Green "✓ Favorable":** the whole school interval is strictly on the favorable side.
- **Red "× Unfavorable":** the whole interval is strictly on the unfavorable side.
- **Yellow:** "≈ Overlaps" when the intervals overlap; "≈ Touches" when they only share an endpoint (e.g. 0%–20% against exactly 20%).
- **Outlined "= Matches":** equal exact values.
- **Gray "–":** not compared, always with the reason.
- Direction is reversed for lower-is-better measures.
- **Evidence for reading ranges as published bounds:**
  - Insights Data page: identifiable data is "converted to a range of values".
  - NDUS Institutional Research: "exact values are often replaced with value ranges".
  - SLDS policy: ranges are an approved suppression method.
- **Remaining uncertainty, stated plainly in the legend and every explanation:** rounding and endpoint meaning are undocumented (does 29% mean "up to 29%" or "below 30%"?). So a color compares published values. It is not a statement about the exact hidden value or an official determination.

**Participation target** (% tested):
- **Source:** 20 U.S.C. 6311(c)(4)(E)(i) requires measuring "not less than 95 percent of all students, and 95 percent of all students in each subgroup" on the reading/language arts and mathematics assessments. Insights' participation charts note the same 95%.
- **Applied only to:** ELA and math, Combined assessment (standard plus alternate), all students, the school's All Grades row.
- **Not applied, as "No target" with the reason:**
  - science (outside the requirement);
  - other assessment types;
  - student groups (Insights' groups aren't verified as the federal subgroups);
  - single grades;
  - survey participation (no documented target).
- **Rule:**
  - lower bound at least 95%: green "Meets 95% target";
  - upper bound below 95%: red "Below 95% target";
  - range crosses 95%: yellow "Cannot determine (95% target)".
- Fort Yates 2024-25 is 95%–97% for both ELA and math, so it is **green**.
- Labeled a dashboard comparison of published values, not an official compliance finding.

**Engagement benchmark (investigated October 31, 2026):**
- **Sources:**
  - ND Student Engagement Survey technical briefs (Cognia) for 2021-22, 2022-23, 2023-24 and 2024-25 (2024-25: V1.0, April 3, 2025; https://nddpi.onlinehelp.cognia.org/wp-content/uploads/sites/20/2025/04/ND-2425-SES-Technical-Brief.pdf).
  - Stored with their SHA-256 under `references/nd_insights/ses_briefs/`. The arithmetic is recorded in `references/nd_insights/verification/ses_benchmark_2026-10-31.json`.
- **Instrument and definition:**
  - The Cognia SES has elementary (grades 3–5), middle (grades 6–8) and high (grades 9–12) versions.
  - Each student is classified by their modal engagement type in each domain, reported as a share of respondents who completed the survey (brief §2 and §6).
  - Figures 4–6 give respondent counts for Committed, Compliant and Disengaged by span and domain. Each domain sums to the span total in Table 2.
- **The Insights state row is the grades 3–12 aggregate:**
  - For 2021-22 and 2024-25, summing the three spans' counts and dividing by all respondents reproduces every Insights "State of North Dakota" Committed and Disengaged value for Behavioral, Cognitive and Emotional to two decimals.
  - Example: 2024-25 Behavioral Committed 40,857 / 80,214 = 0.509, and Insights shows 0.51.
  - This confirms the same definition and aggregation, and that the state row isn't a middle-school figure.
- **The school figure's population** (brief Appendix C lists each school's respondents by survey version, with % Committed per domain):
  - **2024-25:** Fort Yates is listed only under the middle version (98 respondents; 34/31/31%), each inside its Insights range (30%–34%). Same population: **compared**.
  - **2021-22:** middle version only (52; 19/27/25%), inside 15–19/25–29/25–29%. **Compared.**
  - **2023-24:** elementary 7 plus middle 46. The middle-only Behavioral 41% is outside Insights' 45%–49%; the respondent-weighted mix (about 45%) is inside. So the Insights figure includes elementary-version respondents. **Not compared.**
  - **2022-23:** elementary 13 plus middle 42; middle-only Cognitive 38% is outside 40%–44%. **Not compared.**
  - **2017-18 to 2020-21:** no brief recorded or verified. **Not compared.**
  - The seeded grade span is 5–8, which is consistent with elementary-version respondents in some years.
- **How the benchmark is used:**
  - Same-year Figure 5 counts are used as published proportions (e.g. 2024-25 Behavioral Committed 12,136 of 24,900).
  - Only Committed (higher is favorable) and Disengaged (lower is favorable) are rated. Compliant stays neutral.
  - Overall has no grade-span figure in the briefs, so it is context only.
  - Years are never mixed, and the grades 3–12 row is never substituted.
  - When no benchmark applies, a highlighted note above the Engagement table names the reason (e.g. "Elementary 7 and Middle 46").
- **Fort Yates 2024-25:**
  - Behavioral Committed 30%–34% vs 48.7%: red. Behavioral Disengaged 15%–19% vs 10.2%: red.
  - Cognitive Committed 30%–34% vs 35.4%: red. Cognitive Disengaged 10%–14% vs 12.5%: yellow.
  - Emotional Committed 30%–34% vs 33.7%: yellow. Emotional Disengaged 40%–44% vs 24.0%: red.
- **2021-22:** 1 green, 4 red, 1 yellow.
- **Insights data defect noticed:** in the Behavioral, Cognitive and Emotional downloads, the state "Compliant" value equals "Committed" every year (e.g. 2024-25 Behavioral 0.51 and 0.51, with Disengaged 0.09). That can't be a distribution. Compliant isn't rated, so nothing depends on it, but it is reported here (item 31).

**Explanations:**
- **Legend** (`#nd-color-legend`): the three comparison kinds, the colors, and the published-values caveat. The text is shared with the PDF.
- **All Grades:** gray All Grades rows are explained beside each table, with both grade spans (`#achievement-coverage`, `#growth-coverage`). For example, Math this school 6, 7, 8 · North Dakota 3, 4, 5, 6, 7, 8, 10; Growth this school 7, 8 · North Dakota 4–8.
- **Engagement benchmark status** (`#engagement-benchmark`) sits above the Engagement table.
- **Each cell's label** opens its explanation: the benchmark or target value, the source, and why the cell has its color.
- **PDF:** the same tones, labels and section notes; a "Why values are gray" list; and sources for the briefs and the statute.

**Fort Yates 2024-25 totals (Combined, all students; dev data, read only):**

| Section | Red | Green | Yellow | Gray |
|---|---|---|---|---|
| Achievement | 13 | 2 (% tested) | 8 | 37 |
| Growth | 4 | 2 | 10 | 26 |
| Engagement | 4 | 0 | 2 | 6 |

- **Gray, each with its reason:**
  - All Grades with different grade coverage;
  - intermediate levels;
  - the overall growth level;
  - % tested outside the target's scope;
  - Engagement Overall and Compliant.

**Unchanged:**
- Annual-target goal status.
- The percentile goals (38/43/51, 41/46/52) and the explicit year-selection and save workflow.
- Actual records (none added), payment, and Fort Yates only.

### Polish and stabilization (October 31, 2026, Fort Yates)

**Wording:**
- **Four kinds of missing value:**
  - "Not reported": no actual result submitted.
  - "Not rated": no implementation rating submitted.
  - "Intermediate level" or "No documented direction": a published value deliberately not rated (state cells; formerly "Not rated").
  - "No ND value" or "ND suppressed": no usable benchmark.
- **Incompatible populations** are "Context only", with the reason beside the table.
- **Earlier years:** "goals start in 2025-2026, so 2024-2025 results are not evaluated against them; they are still compared with North Dakota for the same year" (`#achievement-goal-years`).
- **Goal 4 note:** the payment formula averages column I, so a 0–3 rating entered there would count as a review rating. Targets and actual results are not ratings and never produce a payment.

**Dashboard:**
- **Summary cards:** compact. Payment weights and the cap sit in a disclosure (`#payment-details`).
- **Legend:** short and always visible (`StateComparison.legend_short`). Methodology and sources are in `#nd-methodology`.
- **Engagement:** one visible summary line; the reconciliation details are in `#engagement-benchmark-details`. A not-compared year keeps its highlighted reason.
- **Checked:** keyboard (Enter opens every disclosure), light and dark themes, and 390px mobile (no horizontal scroll).

**PDF:**
- **Cells:** compact status labels (e.g. "Unfavorable", "Intermediate", "Meets 95%") with the benchmark printed under each value ("ND 25%", "ND gr. 6–8 48.7%", "Target 95%").
- **Pagination:**
  - Table headings and their notes are sticky with the table header and first rows.
  - Guidance and appendix list items never split.
  - A deliberate page break comes before "Appendix: methodology and sources".
- **Growth columns** were rebalanced, so labels wrap to at most two lines and nothing collides; no text was shrunk.
- **Guidance:** one short "How to read this report" list replaces "Why values are gray" and the old notes. Detailed methodology (published values, matching, directions, 95% target, Engagement checks, annual targets, growth percentiles, workbook provenance, open confirmations) is in the appendix.
- **Workbook provenance:** shown as `[W] <cell>` per row, with "the workbook does not record who entered each value" stated once in the appendix.
- **Sources:**
  - "Sources used in this report" covers the selected year's files, the Engagement files, the cited growth-percentile year, the brief when used, and the statute only when % tested was compared.
  - "All imported ND Insights files" is listed separately as an inventory.
- **Optional comparison table:** short benchmark values and explanations without the repeated caveat.
- **Rendered and read page by page:** default (7 pages), with the comparison (12 pages), and 2023-24 (7 pages).

**Evidence, now tracked:**
- `docs/nd_insights_benchmarks.md`: sources with SHA-256, the figures and pages used, the counts, both reconciliation checks, the Fort Yates compatibility table by year, the data defect, and reproduction steps.
- `test/emisint/nd_insights/survey_benchmark_evidence_test.exs`: reproduces from the brief counts and the tracked fixture that each span sums to its total, that all spans reproduce the Insights state values, and that the middle-only years reconcile. The briefs themselves stay in git-excluded `references/`.

**Rechecked source questions (no documented decision found):**
- The workbook still has `Ft Yates Goals!P7` = 90 and `P16` = 80 in General format, while other targets are decimals (e.g. `O6` 0.9).
- `I26` is still "Target Check".
- No cell comments (the threaded comments on `F3`/`F12`/`F19`/`F26` are review narratives), repository documents or recorded decisions resolve them.
- The flags stay (items 1–3 below).
- **Needed:**
  - Whether 90 and 80 mean 90% and 80%.
  - Whether Goal 4's column I holds 18-month review ratings.
  - What column Q "Target Check" (3/2/1/0/N/A) means.

### Provisional payment rule (November 1, 2026, Fort Yates)

- **Authorization:** Ram authorized using a best-estimate payment rule until the actual terms are confirmed. The specifics are our selections, not terms he specified: $70,000 total per school across both checkpoints and an equal $35,000 per checkpoint. The weights are those confirmed October 23, and the formula `allocation × weighted review score ÷ 3` is the workbook's documented mapping. Details under "Payment".
- **Data changes (dev):** migration `20261101180000_add_provisional_payment_estimates` (hand-written; five `improvement_goal_plans` columns and the `improvement_payment_estimates` table; snapshots `improvement_goal_plans/20261101180000.json` and `improvement_payment_estimates/20261101180000.json`). Fort Yates' plan was moved to the provisional terms through `:set_payment_terms` (terms v1 → v2; the note was corrected to the wording above in v3); no ratings, actual results or payments were invented or changed.
- **Incident and recovery:** running `mix ash.codegen add_provisional_payment_estimates --dry-run` rolled back the teammate's `_dev` migration in `emisint_dev` (dropping `mde_sss_schools`, `mde_sss_comparison_groups`, `mde_sss_comparison_group_members`) and deleted its migration and three snapshots from the working tree.
  - The four files were restored from HEAD (they had no uncommitted edits).
  - The tables were recreated with `mix ecto.migrate --to 20260701032125` (that migration only). **This restored their structure, not any rows.**
  - **Whether the tables held rows is unknown.** Evidence suggests they were empty, but it is not proof: SSS data enters through the admin upload, which writes an `mde_import_logs` row and an Oban job; the dev database keeps both (no pruner; jobs since June 2026) and has none for SSS, no seed loads SSS data, and the local upload directory doesn't exist. Rows inserted any other way (a console, a script, a restored dump) would leave no such trace.
  - **Backups:** No usable backup was found in the locations checked; Time Machine was inaccessible. Checked: Postgres WAL archiving (off), dump/SQL/backup files under the home folder (four levels deep, excluding `~/Library`), and local APFS snapshots (none). Not checked: Time Machine (its destination failed to mount) and the Postgres server log directory (permission denied). If the tables did hold data and no backup turns up, it must be re-imported from the MDE SSS file via Data Import.
  - Prevention: unresolved item 13.

### State results colored by school goals (November 1, 2026, Fort Yates)

The main Achievement, Growth and Engagement tables (dashboard and PDF) now show progress against the school's own goals. North Dakota comparisons are only in the separate "North Dakota comparison" section (collapsed on the dashboard; `nd_comparison=1` in the PDF), which is unchanged in function.

- **Shared module:** `Improvement.ResultGoals` (matching, status, short label, goal line, explanation, legend and methodology text), used by `StateResultsComponents` and `NdFirstSchoolPdf`. It never reads North Dakota rows, so main-table statuses are independent of them.
- **Explicit matches only** (Fort Yates workbook goals match only Fort Yates, by metric code and `performance_measure`):
  - Proficient alone → G2-M1 (ELA), G3-M1 (Math).
  - Novice → G2-M2, G3-M2; lower is better.
  - Proficient or Advanced (derived) → the annual target (`AnnualAssessmentGoal`) of the same school year; Combined only when it includes the alternate assessment.
  - Overall growth percentile → G2-M3 (ELA), G3-M3 (Math), in percentiles (no % sign).
  - Engagement Disengaged by domain → G4-M2 (Emotional), G4-M3 (Behavioral), G4-M4 (Cognitive), always neutral: "Not compared: population unverified" (item 23). G4-M1 (observed active engagement) is never matched to survey Committed.
  - Every goal is schoolwide: only the All Grades row for all students. No target is applied to a grade or a student group. Other measures (Approaching Proficiency, Advanced, growth categories, Meets or Exceeds, growth level, Committed, Compliant, Overall engagement) have no goal and stay plain.
- **Timing:**
  - Annual targets apply only to their own school year.
  - Workbook targets are judged only when the checkpoint's assessment year is explicitly established (`ResultGoals.established/0`, `review_years`). None is established (item 27), so they show "Reference only" with both targets.
  - A result from another year than an established review year is reference only, never met or failed.
  - The workbook's assessment type (Combined, Standard or Alternate) is also not established; workbook achievement targets are not judged until it is (item 32).
  - Nothing is saved: the published value is never treated as a review result. The explicit select-and-save workflow (`FromNdInsights`, `GoalStatus`) is unchanged, and there is no blanket year cutoff.
- **Verdicts:** only exact published values against numeric targets, respecting direction; equality meets. A published range is "Pending range clarification" with no verdict (the same rule as `SchoolResults.compare_goal/2`, which the annual match reuses); the North Dakota endpoint policy is not used for goals. No midpoints or tolerances.
- **Colors and labels:** green "Meets goal", red "Below goal"; no color (with a label and an explanation) for reference only, unverified population or assessment type, pending range, suppressed or missing. A value with no matching goal has no label. Proficient no longer shows "Intermediate level".
- **% tested:** the 95% participation target is a text label ("Meets 95% participation target") only where it applies (ELA and math, Combined, all students, All Grades). It never fills the cell and is not a goal status.
- **Fort Yates today (2024-25 data, dev):** no main-table value receives a goal color.
  - G2-M1, G2-M2, G3-M1, G3-M2 (All Grades Proficient and Novice): reference only, since no review year is established. The values are also published ranges, and the workbook's assessment type is unknown.
  - G2-M3 and G3-M3 (growth percentiles 38 and 41, exact): reference only, since no review year is established. Once one is, an exact percentile would get a verdict.
  - G4-M2, G4-M3, G4-M4: not compared, because the population is unverified.
  - Proficient or Advanced: there is no annual goal for 2024-25 (the goals start in 2025-26). The 2025-26 values, once published, will be compared, but a range will stay pending.
  - % tested 95%–97% (ELA and math): meets the 95% participation target, shown as a label.
- **Tests:** `test/emisint/improvement/result_goals_test.exs` (matching, mismatched grades and subgroups, assessment type, other schools, engagement, historical results, unresolved review years, lower-is-better, exact equality, published ranges, suppressed). LiveView and PDF tests check that the main tables carry no North Dakota labels or fills and are identical with or without the comparison export, and that the ND section keeps its legend, coverage notes, Engagement check and table.

### Demo: reference comparisons against school goals (November 2, 2026, Fort Yates)

Supersedes the verdict, timing and color rules of "State results colored by school goals" above. Its matching rules are unchanged.

- **Rule** (`ResultGoals`, shared by the dashboard and the PDF). This is a dashboard comparison rule, not an official ND FIRST scoring method. Published bounds are compared with the target; an exact value has equal bounds, and equal meets. No midpoints or tolerances.
  - **Higher is better:** a lower bound at or above the target meets (green), an upper bound below it misses (red), otherwise the range overlaps (amber).
  - **Lower is better:** an upper bound at or below the target meets, a lower bound above it misses ("Above target"), otherwise it overlaps.
- **Reference checkpoint:** the "Compare with" select (`goal_ref=18m|36m`) sits in the state filters and travels to the PDF.
  - Workbook goals are compared with the selected target and labeled "Reference comparison against future target" (a result from before `FortYates.plan_start_year/0`, 2025-2026) or "Reference comparison — review year unconfirmed".
  - Selecting a checkpoint changes only the display. It doesn't save actuals, set ratings or feed the payment estimate; a LiveView test checks that the record counts and the payment status are unchanged.
- **Annual targets:** same school year only; another year's target is never substituted.
  - The Annual targets table keeps `SchoolResults.compare_goal/2` (ranges pending).
  - The state tables apply the dashboard rule to the same targets. That inconsistency becomes visible only once 2025-26 data is published.
- **Gray, with the target shown:** the workbook's assessment type is unconfirmed (G2-M1, G2-M2, G3-M1, G3-M2); the survey population is unverified (G4-M2, G4-M3, G4-M4); or the value is missing or suppressed. No shading means the measure has no school goal. % tested stays a participation-target label.
- **Fort Yates today (2024-25, 18-month reference):**
  - Red: G2-M3 ELA growth percentile 38 vs 43, and G3-M3 Math 41 vs 46 (36-month: 51 and 52). Both are "against future target".
  - Gray: Proficient and Novice (assessment type), Disengaged (population).
  - No annual goal for 2024-25.
- **To get more colors (decisions, not code):**
  1. The assessment type of the workbook's Proficient and Novice targets. Set it in `ResultGoals.established/0`. For Fort Yates the Combined and Standard rows are identical, but that doesn't establish the workbook's meaning.
  2. The survey year and grades behind G4-M2, G4-M3 and G4-M4.
  3. The 2025-26 Insights download, for the annual targets.

### Demo assumptions for goal colors (November 2, 2026, Fort Yates)

Supersedes the "Gray: assessment type unconfirmed" and "Gray: survey population unverified" rules in the section above.

- **Demo assumptions** (`ResultGoals.demo_assumptions/0`): configurable, **not verified facts**, and applied only to Fort Yates workbook reference comparisons.
  1. **Assessment type:** the workbook's Proficient and Novice targets (G2-M1, G2-M2, G3-M1, G3-M2) count the Combined assessment, all students, All Grades. Standard and Alternate views therefore get no workbook verdict; a note says so.
  2. **Engagement population:** the disengagement targets (G4-M2 Emotional, G4-M3 Behavioral, G4-M4 Cognitive) count the school's schoolwide survey population.
  - Passing `assumptions: %{}` restores the gray "unconfirmed" behavior. Once the real meaning is confirmed, record it in `established/0` instead.
- **Section notes, once per table:**
  - Achievement: "Reference comparison; Combined assessment assumed for workbook targets."
  - Engagement: "Reference comparison; schoolwide survey population match assumed."
  - Growth: "Reference comparison against workbook targets."
  - Each adds "‹year› results predate the plan, so they are compared against future targets" where that applies.
- **Annual Targets table:** now uses `ResultGoals.annual/2`, the same bound rule and wording as the state tables, on the website and in the PDF. Same-year matching is unchanged. `SchoolResults.compare_goal/2` still derives the value but no longer decides the color.
- **Unchanged:** the matching rules, schoolwide-only scope, percentile units, no matching of G4-M1 to Committed, the ND section, provisional payment terms, and the separation from saved actuals, ratings and payment. A LiveView test confirms that changing the reference saves nothing.
- **Fort Yates 2024-25, All Grades, all students, Combined:**

| Cell | Published | 18-month target | 36-month target |
|---|---|---|---|
| ELA Novice (G2-M2, lower is better) | 40%–49% | 39%: red (above) | 31%: red |
| ELA Proficient (G2-M1) | 20%–29% | 27%: amber | 32%: red |
| Math Novice (G3-M2, lower is better) | 70%–79% | 72%: amber | 68%: red |
| Math Proficient (G3-M1) | 0%–10% | 8%: amber | 12%: red |
| ELA growth percentile (G2-M3) | 38 | 43: red | 51: red |
| Math growth percentile (G3-M3) | 41 | 46: red | 52: red |
| Behavioral Disengaged (G4-M3) | 15%–19% | 12%: red | 8%: red |
| Cognitive Disengaged (G4-M4) | 10%–14% | 7%: red | 5%: red |
| Emotional Disengaged (G4-M2) | 40%–44% | 32.9%: red | 22.9%: red |

  - Proficient or Advanced: no 2024-25 annual target, so no color (none is substituted).
  - Grade and subgroup rows, other levels, Committed, Compliant and Overall engagement: no goal, no shading.

### Grade-level reference colors (November 2, 2026, Fort Yates Achievement)

- **Scope:**
  - ELA and Math, grades 6–8, Novice and Proficient alone, Combined assessment, all students, under the Combined demo assumption.
  - Fort Yates only.
  - Each grade is compared with the **schoolwide** workbook target (G2-M1, G2-M2, G3-M1, G3-M2) at the selected 18- or 36-month checkpoint, using the same bound rule.
  - Not applied to subgroups, Standard or Alternate views, Science, Approaching Proficiency, Advanced, growth or engagement grade rows, or other schools. Annual-goal year matching is unchanged.
- **Labels** (`ResultGoals`, `kind: :grade_reference`):
  - "At or below / Above schoolwide target" for Novice; "At or above / Below schoolwide target" for Proficient; "Range overlaps schoolwide target".
  - Then "Schoolwide reference: ‹target› · ‹18-/36-month›".
  - A note above the table: "Grade-level colors compare each grade’s results with the schoolwide target for reference. These are not separate grade-level goals."
  - No grade is labeled as meeting or failing its own goal.
- **Unchanged:**
  - The All Grades comparisons and labels (a test confirms they are identical with or without grade rows).
  - The section notes, including future targets.
  - Saved actuals, ratings and payment.
  - No averaging of grade percentages into a schoolwide value.
- **Fort Yates 2024-25 (18-month / 36-month):**
  - ELA Novice, grades 6–8 (40–49%, 60–69%, 40–49%): red at both (39% / 31%).
  - ELA Proficient, grades 6–7 (0–20%): red at both (27% / 32%). Grade 8 (40–49%): green at both.
  - Math Novice: 18-month 72%: grades 6 and 8 (70–79%) amber, grade 7 (80–100%) red. 36-month 68%: all red.
  - Math Proficient, grades 6–8 (0–20%): amber at both (8% / 12%).

### Range boundaries and grade-level Growth references (November 2, 2026, Fort Yates)

- **Boundary rule:** verified correct, now one public function, `ResultGoals.classify/3`, used by Achievement, Growth, Engagement, the annual targets and the PDF.
  - **Higher is better:** low ≥ target meets; high < target misses; otherwise overlaps.
  - **Lower is better:** high ≤ target meets; low > target misses; otherwise overlaps.
  - **Examples at target 20:**

    | Direction | 20–30 | 10–20 | Exact 20 |
    |---|---|---|---|
    | Higher is better | meets | overlaps | meets |
    | Lower is better | overlaps | meets | meets |

  - **Correction:** an earlier report said a range ending exactly on the target "counts as overlap". That holds only for higher is better; for lower is better a range touching the target from below meets. Boundary tests now cover both directions in every section.
- **Grade-level Growth references:**
  - **Scope:** Fort Yates, ELA and Math, grades 6–8, all students.
  - **Measure:** the overall growth percentile only, against the schoolwide G2-M3 / G3-M3 target read from the metric records. No percentile target goes on the growth categories, and no assessment-type restriction applies, since growth has no assessment-type breakdown.
  - **Labels:** "At or above / Below schoolwide target" and "Range overlaps schoolwide target", then "Growth percentile target: ‹target› · ‹18-/36-month› · Schoolwide reference" (relabeled in the PDF-review polish below). A note above Growth says these are not separate grade-level goals.
  - **Unchanged:** All Grades comparisons; display only; never averaged.
- **Fort Yates 2024-25 published grade percentiles** (no grade-6 growth row is published):

  | Row | Percentile | 18-month | 36-month |
  |---|---|---|---|
  | ELA grade 7 | 35 | red (43) | red (51) |
  | ELA grade 8 | 64 | green (43) | green (51) |
  | Math grade 7 | 58 | green (46) | green (52) |
  | Math grade 8 | 41 | red (46) | red (52) |

### PDF review polish (November 2, 2026, Fort Yates)

- **Methodology wording:** the "Matching" paragraph (dashboard "How results are matched to goals" and the PDF appendix, both from `ResultGoals.methodology/0`) no longer says "never a single grade". It now says that schoolwide results (All Grades, all students) match the schoolwide goals, and that eligible grade-level Achievement and Growth results are compared with those same schoolwide targets for reference, not separate grade-level goals.
- **Payment text, said once:**
  - `Payment.terms_text/1` for provisional terms is now only the provisional sentence. The summary (`terms_summary/1`) still states the cap and split.
  - The PDF guidance no longer restates "working assumptions pending clarification". The page-1 note no longer promises a "source of these assumptions" in the appendix.
  - The stored notes and recorded estimate snapshots are unchanged.
- **Growth percentile labels:** these now read "Growth percentile target: 43" (workbook: "2024-2025 result · Growth percentile target: 43 · 18-month · G2-M3"; grade reference: "Growth percentile target: 43 · 18-month · Schoolwide reference"). The verdict now says "18-month growth percentile target 43". There is no percent sign.
- **PDF cell readability:**
  - Notes are 7pt (was 6.5pt), in a darker slate.
  - Each "·" part of the goal line starts its own line. Values and notes don't break inside "20%–29%", "18-month", "G2-M3" or "target: 43".
  - The Achievement and Growth column widths were rebalanced toward the goal columns. Rows are still unsplittable.
- **Unchanged:** targets, matching, colors, ratings, payment amounts, weights, formulas and stored data.

### Expansion: source audit and Oberon (November 4, 2026; branch `nd-first-dashboard`)

Scope: Drayton, Dunseith, Mandaree, Oberon, Valley Middle School and Warwick, one school at a time. Oberon is implemented; the others are audited only and shown as "Coming soon". Cannon Ball is deferred.

**Sources checked.**
- **Goals workbook:** the Google Sheet (exported November 4) matches the local `references/ND First School MOU Goal Overview.xlsx` cell for cell on every school sheet. Only "Example School" (G4, G7) and "Evidence Tracker" differ.
- **Annual goals document:** the Google Doc export returned 401 (not shared publicly), so `references/North Dakota - ND First Schools.pdf` (31 pages) was used.
- **ND Insights statewide CSVs** in `references/nd_insights/` (17 files, 2021-22 to 2024-25 plus the Engagement files). No new downloads were needed for Oberon.

| School (workbook tab) | Verified building ID(s) in Insights | Grades published in Insights | Workbook sheet | PDF annual targets | Gaps before implementation |
|---|---|---|---|---|---|
| **Oberon** (`Oberon Goals`) | 0301662261 Oberon Elementary | All Grades only (no grade rows); performance 2021-22–2023-24, none for 2024-25; growth 2021-22–2023-24; participation 2021-22–2024-25; engagement 2018-19–2024-25 | 4 goals, 21 metrics (9 Systems, 12 Student Outcome) | p.23: historical goal period 2018-19–2023-24 only | See "Oberon open items" |
| **Drayton** (`Drayton Goals`) | 3401919281 Drayton Elementary; 3401919283 Drayton High School | Elementary 3–8 (growth 4–8); High School 10 | 5 goals, 13 metrics, written for "Drayton Public School(s)" (district) | p.7–10: 2025-26–2030-31 | Which building(s) each metric covers; targets like "< 10%", "> 2", "Not monitored" / "Monitored" |
| **Dunseith** (`Dunseith Goals`) | 4000119681 Dunseith Elementary; 4000119663 Dunseith High School | Elementary 3–8 (growth 4–8); High School 10 | 6 goals, 16 metrics, written for "Dunseith Public Schools" | p.12–16: 2025-26–2030-31 (PDF says it "assume[s] the same six-year sequence") | Campus split (H5/H10 read "50% K-6; 100% 7-12"); text targets ("70% @ Level 2+", "n/a", "< 1.7") |
| **Mandaree** (`Mandaree Goals`) | 2703654591 Mandaree Elementary; 2703654593 Mandaree High School | Elementary 3–8 (growth 4–8); High School 10 | 6 goals, only 6 metrics (one per goal); Goal 1 names grades 3–10 | p.19–22: 2025-26–2030-31 | Grades 3–10 span two buildings; text targets ("< 2.4", "> 50%") |
| **Valley Middle School** (`Valley Goals`) | 1800189752 Valley Middle School | 6–8 | 7 goals, 26 metrics; already seeded (dev DB) | p.25–26: 2025-26–2030-31 | 43 non-numeric baselines/targets ("> 50%", "< 22% or within 7% State Avg", "n/a"); Measure 1 and English Learner targets not stored (earlier note) |
| **Warwick** (`Warwick Goals`) | 0302992191 Warwick Elementary; 0302992192 Warwick Middle School; 0302992193 Warwick High School | Elementary 3–4; Middle 5–8; High School 10 | 5 goals, 25 metrics, written for "Warwick School" | p.27–30: 2025-26–2030-31 | Three buildings; relative targets ("Dec 2-3%", "Inc 4-6%", "Another core") need a baseline-year rule |

Every school's payment row ("Performance-Based Payment" rows 3–11) uses the same 70%/30% formula and "up to $70,000" header. Only Fort Yates has provisional allocations; nothing is assumed for the others.

**Shared school tabs.**
- `Emisint.Improvement.Pilot.roster/0` lists the tabs in this order: Fort Yates, Oberon, Drayton, Dunseith, Mandaree, Valley Middle School, Warwick.
- A tab is enabled only for a configured pilot InstitutionID (`config :emisint, :nd_first, pilot_institution_ids: ["4300429212", "0301662261"]`).
- `EmisintWeb.Improvement.Components.school_tabs/1` renders "ND FIRST School Dashboard" with one tab per school on the landing page and on every school dashboard.
- The selected tab has `aria-current="page"`. Each enabled school links to its own URL (`/school-goals/:slug`).
- Disabled tabs are plain text with a "Coming soon" badge. They have no link and show no data. Valley is labeled "Coming soon" even though its definitions are seeded.

**Per-school comparison configuration.**
- `ResultGoals.config/1` reads each school's `comparison/0` from its definition module, found by InstitutionID through `Seeds.module_for/1`. That config holds the metric mapping, assumptions, grade references, plan start year and wording.
- Fort Yates's mapping, demo assumptions, grades 6–8 references and texts moved unchanged into `Seeds.FortYates.comparison/0`.
- A school without a definition module gets no workbook match and no notes.
- Two new gray reasons:
  - `:target_is_range`: a target written as a range, e.g. "55-60%". The workbook doesn't define when a range target is met.
  - A derived Proficient-or-Advanced value that can't be derived.
- Annual targets with no matching result now say "Not yet published" (no later results imported) or "No result imported" (an earlier year whose download isn't on file).

**Oberon implementation** (`Seeds.Oberon.comparison/0`).
- **Metric mapping**, from Oberon's own wording, guarded by the exact workbook text because Oberon's metrics are stored with `performance_measure: :other`:
  - G1-M1 / G2-M1 "Proficient & Advanced" → derived Proficient or Advanced (ELA / Math).
  - G1-M2 / G2-M2 → Novice (lower is better).
  - G4-M1 / G4-M2 / G4-M3 → Emotional Committed / Compliant / Disengaged (Disengaged lower is better).
  - Not matched (no ND Insights counterpart): Goal 3 attendance, G4-M4 referrals and the Systems metrics. Oberon has no growth metric.
- **No assumptions.**
  - The workbook doesn't name the assessment behind its achievement targets, and its baselines don't match Insights (ELA Novice baseline 36% vs 50%–79% published), so workbook achievement cells are gray: "assessment type unconfirmed".
  - Engagement targets are ranges, so they are gray: "target is a range".
  - No grade-level references, since Insights publishes none for Oberon.
- **Annual targets:** PDF p.23's historical goal period, 2018-19–2023-24. 2021-22 to 2023-24 are compared with their own year's published derived values (all overlap). 2018-19 to 2020-21 read "No result imported". Where a same-year annual target exists it takes the Proficient-or-Advanced cell; otherwise the workbook's G1-M1 / G2-M1 target does.
- **Payment:** the plan has a $70,000 cap but no checkpoint allocations (`payment_terms_status: unconfirmed`). The card, table, details and PDF read "Estimated payment — not configured" / "Not configured". No Fort Yates split is copied.
- **Imports:** `mix nd_insights.import --institution-id 0301662261 references/nd_insights/*.csv` created 232 Oberon measures (280 in total with the 48 already stored), with 0 conflicts. A second run created 0 and left 280 unchanged. The school import page `/school-goals/oberon-elementary/import` is locked to Oberon.
- **Unchanged:** Oberon's existing goals, metrics, ratings and provenance in the dev database (the seed is drift-safe and was not re-run).
- **No schema changes, migrations or code generation.**

**Oberon open items (not guessed).**
1. The assessment type (Combined, Standard or Alternate) and the source and year behind the G1-M1, G1-M2, G2-M1 and G2-M2 baselines.
2. A rule for range targets (G3-M2, G4-M1 to G4-M3): does "55-60%" mean the lower bound, the whole range, or the band the published range must fall in?
3. G4-M7's 18- and 36-month targets: the cells hold the date February 3, probably "2-3" converted by the spreadsheet.
4. G1-M3 and G1-M4 have no baseline.
5. The grade span isn't stated in the sources.
6. Annual targets for 2024-25 and later. The PDF shows only the historical period.
7. Payment allocations per checkpoint.
8. No 2024-25 performance or growth rows are published for Oberon; the cause (suppression, or no tested students) isn't stated.

**Verification.**
- Headless Chrome: Oberon at both checkpoints, 2023-24 and 2024-25; Fort Yates at 18 months; Oberon at phone width (no page overflow).
- Every page of three Oberon PDFs was inspected: 2024-25 default (6 pages), 2023-24 at 36 months (6) and 2023-24 with the ND comparison (9). Fort Yates's PDF is still 7 pages.
- Text scans of the Oberon PDFs found no "Ft Yates", Fort Yates, $35,000, G2-M3 or Fort Yates assumption text.
- Fixed while checking: the ND comparison said a school with no grade rows "covers grades none". It now reads "grades not published".
- Tests:
  - `oberon_result_goals_test.exs` (13): mapping, no assumptions, both checkpoints, annual precedence, range targets, wording.
  - `oberon_live_test.exs` (9): tabs, switching, comparisons at both checkpoints, annual targets, update and history scoping, membership and organization isolation, PDF data, locked import and repeat import.
  - Updated: `additional_schools_live_test.exs` (Oberon is now listed; payment "Not configured") and `payment_estimate_test.exs`.
- Full suite 382/539. The 157 failures are the legacy set exactly; none are new.

### Oberon missing-year fixes and Windows setup (November 8, 2026; uncommitted, pending review)

Scope: Oberon (0301662261) only; Fort Yates checked for regressions. No other school was implemented, nothing was committed or pushed, and there were no schema changes, migrations, database resets or Ash code generation.

**Windows development setup (new PC; the Mac database was not copied).**
- **Toolchain:** Erlang/OTP 27.3.4.18 (winget), Elixir 1.18.6 for OTP 27 (official release zip, SHA-256 checked, in `%LOCALAPPDATA%\Programs\elixir-1.18.6`), PostgreSQL 17.11 (EDB installer, service `postgresql-x64-17`, port 5432), Visual Studio 2022 C++ Build Tools and Rust 1.99.1.
- **Native code:** `bcrypt_elixir` and `picosat_elixir` compile with MSVC (`nmake`). Imprintor 0.1.5 publishes no Windows binary, so it was compiled from source once with `FORCE_COMPILE=1`, inside the Visual Studio x64 environment. Plain `mix phx.server` needs neither afterwards; they are needed again only if those dependencies are recompiled.
- **Credentials:** `PGUSER` / `PGPASSWORD` are Windows user environment variables, read by `config/dev.exs`; nothing is stored in the repo.
- **Known Windows differences:**
  - The template font "Helvetica Neue" is not installed, so PDFs use Typst's fallback font. Page counts are unchanged.
  - LiveView can't symlink `assets/node_modules` for colocated JS without an administrator terminal (a warning only).
  - The checkout uses `core.autocrlf=true`. `mix format --check-formatted` flags CRLF files, so the changed files were saved with LF (git shows no line-ending diff).
- **Database:** `emisint_dev` was created with `mix ecto.create` + `mix ecto.migrate`: all 38 migrations, including the teammate's `_dev` migration, whose SSS tables now exist (empty). Then:
  - `mix run priv/repo/seeds.exs` (Cornerstone demo org);
  - `mix nd_first.seed --dev`: Fort Yates (4 goals, 18 metrics, 36 workbook ratings, 12 annual goals) and 6 dev users;
  - `Seeds.run(dev_org, schools: [Seeds.Oberon])`: Oberon (4 goals, 21 metrics, 42 ratings, 12 annual goals); 0 drift.
- **Reference files:** `references/` was restored from the Mac ZIP (workbook, annual-goals PDF, 17 ND Insights CSVs, SES briefs, verification scripts). All 17 CSVs match `source_manifest.json` SHA-256. Two tracked CRD files differed only in line endings and were kept. The new files are excluded locally in `.git/info/exclude`.
- **Imports:** `mix nd_insights.import --institution-id 4300429212 --institution-id 0301662261 --institution-id 99999 --actor-email sysadmin@example.com` on the 17 files: 0 conflicts, 0 parse errors, 0 name mismatches. Fort Yates 1,156 measures, Oberon 280 (the same as the Mac), North Dakota 34,015.
  - The earlier "35,070 state measures" figure (October 31) is not a count of these files' 99999 rows (they hold exactly 34,015). Its origin was not established.
- **Check A repeated (database vs CSV):** an independent script parsed the CSVs by header name and compared every measure for 4300429212, 0301662261 and 99999: 35,451 / 35,451 match on value state and both bounds, with 0 missing, 0 extra and 0 mismatches.

**Oberon 2024-25 in the source files (unchanged by this work).** Participation has 14 rows (Combined and Standard; Reading and Math for All, Female and Male; Science for All). Engagement has all five areas, and survey participation is 90%–94%. The 2024-25 Performance and Growth files have **no Oberon rows**, so achievement and growth stay missing: nothing is zero-filled and no reason is given (open item 8 stands). From the data, the latest year with matching achievement and growth for Combined, all students is 2023-2024.

**Fixes.**
1. **Student Group select** (`SchoolResults.subgroups/3`, `resolve_filters/2`, `StateResultsComponents`):
   - **Cause:** the options came only from that year's achievement and growth rows. For Oberon 2024-25 that list was empty while the filter resolved to "All", so the select rendered blank.
   - **Options now:** "All students" is always offered, first. Groups come from the year's achievement and % tested rows for the selected assessment type, plus growth rows (which have no assessment type).
   - **One option:** the select is disabled and shows "All students", with "Only all students published for this year and assessment" (`#state-subgroup-only`).
   - **Stale groups:** the disabled select isn't submitted, so the `state_filters` handler clears a stale `state_subgroup` from the URL.
2. **% tested without achievement** (`SchoolResults.performance/4`):
   - A subject and grade with a published % tested but no achievement levels is returned with `levels: %{}`. Its five level cells read "Achievement not published"; the PDF prints "Not published" in each.
   - `ResultGoals.for_filters/3` skips those rows, so a missing result is never compared with a goal. The 95% participation label still applies to % tested.
   - Engagement and survey participation were already independent of achievement; they are confirmed visible for Oberon 2024-25.
3. **Missing-results note and latest-year link** (`SchoolResults.latest_year_with/3`):
   - **Matching:** the latest imported year with achievement for the same assessment type and student group, or with growth for the same student group, read from the stored rows.
   - **Dashboard:** `#achievement-empty` / `#growth-empty` explain that the imported download has no rows for the combination. `#achievement-latest-year` / `#growth-latest-year` link to that year, or say "No imported year has … results for this combination".
   - **Link behavior:** it changes only `state_year`, on click (a LiveView patch), and keeps `period`, `state_type`, `state_subgroup` and `goal_ref`. The selected year is unchanged until the user clicks.
   - **PDF:** the same note, with the year as text ("Latest imported year with achievement results for the same filters: 2023-2024."). The achievement table still prints rows that have only % tested.

**Effect on Fort Yates (intended, same rule):** 2023-24 now shows four % tested rows the dashboard previously dropped: Reading and Math, grades 5 and 6, 80%–100%. The official 2023-24 Participation file publishes them, and the Performance file has no grade 5–6 rows. All other Fort Yates rows, colors and comparisons are unchanged, and 2024-25 is unchanged.

**Verification (November 8, 2026, Windows).**
- **Tests:** new `test/emisint_web/live/improvement/oberon_missing_results_test.exs` (11), with fixtures in `test/fixtures/nd_insights/oberon_missing_years/`: Oberon's rows copied unchanged from the official 2023-24 and 2024-25 Participation and 2023-24 Growth files. It covers:
  - the selected and disabled states, and year and assessment changes (including clearing a stale group);
  - % tested with no goal marks, and 2024-25 engagement;
  - latest-year links that keep filters and change the year only on click;
  - group- and type-specific years;
  - that Fort Yates rows never supply Oberon's year, and that Fort Yates' tables are unchanged;
  - the PDF data for both years;
  - `SchoolResults` unit cases.
- **Results:** ND First, ND Insights and report suites 343/343. Full suite 550 tests, 157 failures, all in the legacy orphaned suites listed under Risks; none in ND First files.
- **Dev server** (http://localhost:4000, `admin@example.com`), rendered pages checked for:
  - Oberon 2024-25: Combined, Alternate and Female;
  - Oberon 2023-24: Combined, Female and Alternate;
  - Fort Yates: default and 2023-24.
  - Neither school's state results mention the other.
- **Isolation:** `viewer@example.com` (Fort Yates viewer) opens Fort Yates but is redirected away from Oberon's dashboard and PDF. `admin@cornerstone-emo.edu` (another organization) is redirected away from both schools.
- **PDFs:** generated through `/school-goals/:slug/report.pdf` with the Windows-built Imprintor: Oberon 2024-25 and 2023-24 (6 pages each), Fort Yates (7). The pages were viewed by rendering the same data and template with the Typst 0.15.1 CLI: Oberon 2024-25, 2023-24 and Female, and Fort Yates 2023-24.
- **Not done:** interactive headless-Chrome checks. On this PC, headless Chrome stopped responding on every authenticated page, including the unchanged `/school-goals` index. LiveView's client reported "view crashed" after a long-poll fallback, while the server logged a successful mount. The cause was not established, and a check in a normal desktop browser is still needed. Select changes and the link click are covered by the LiveView tests.

### Expansion: remaining participants (November 8, 2026; uncommitted, pending individual review)

Scope: Valley Middle School, Drayton, Dunseith, Mandaree and Warwick, in that order. Cannon Ball (Solen) is still deferred. Nothing was committed, pushed or merged; there were no schema changes, migrations, database resets or Ash code generation. The Fort Yates and Oberon records, imports and fixes are unchanged.

**Sources read for each participant.**
- **Workbook:** `references/ND First School MOU Goal Overview.xlsx`. It was read with an OTP-only `.xlsx` reader, and the generator was ported from `gen_school_seed.py`, since Python isn't installed on this PC. The port reproduces the committed Oberon and Valley `goals/0`, `metrics/0`, `workbook_ratings/0` and last-updated date exactly.
- **Annual-goals PDF:** `references/North Dakota - ND First Schools.pdf`. Pages were rendered with the Windows PDF API and read page by page: Drayton pp.7-11, Dunseith pp.12-15, Mandaree pp.19-21, Valley pp.25-26, Warwick pp.27-31.
- **ND Insights:** all 17 official CSVs. Every InstitutionID below appears under its building name in every dataset. District names vary by file (e.g. "Drayton 19" and "Drayton Public School District"); the importer links by ID and reports the name difference.
- **Payment:** "Performance-Based Payment" has one row per participant (Warwick 7, Mandaree 8, Dunseith 9, Drayton 10, Valley MS 11) with no allocations, so payment is "not configured" for all five, as for Oberon. Nothing is copied from Fort Yates.

**Scope decision (source-supported).** The Drayton, Dunseith, Mandaree and Warwick sheets are written for the district: "<X> Public School(s) will…", "the district will…", and grades 3-10 spanning an elementary and a high school. The PDF, however, gives annual targets per building. ND Insights publishes the district (5-digit ID) and each building separately. So (`Seeds.Participant`):
- **Participant record (district):** holds the workbook goals, metrics, seasonal ratings and payment row, plus the district's own published rows.
- **Building records:** hold only that building's PDF annual targets, compared with that building's own rows. There are no workbook goals, ratings or payment terms (`payment_cap` nil).
- **No mixing:** district goals are never copied to buildings, building results are never averaged or combined into a district value, and each published row appears only on the record of its own InstitutionID.
- **Links:** the district dashboard links its buildings and each building links its district. Only records the user can read are linked; others are named "(no access)". The school tab opens the district.
- **Building pages:** hide the period selector, seasonal and payment cards, goal tables, "Compare with" selector and payment section, with a scope note instead. The building PDF says "Reporting period: Not applicable" and omits the summary, goals and payment appendix.
- Valley Middle School is a single building (its sheet says "Valley Middle School will…"), so it stays one record.

| Participant | Record (InstitutionID) | Workbook | PDF annual targets (ELA / Math, 2025-26 → 2030-31) |
|---|---|---|---|
| Valley Middle | Valley Middle School (1800189752) | 7 goals, 26 metrics, 52 ratings | 37/31 → 55/51% (pp.25-26) |
| Drayton | Drayton Public School District (34019) | 5 goals, 13 metrics, 26 ratings | none for the district |
| | Drayton Elementary School (3401919281) | — | 21/31 → 45/52% (p.7) |
| | Drayton High School (3401919283) | — | 20/19 → 44/43% (pp.9-10) |
| Dunseith | Dunseith Public School District (40001) | 6 goals, 16 metrics, 32 ratings | none |
| | Dunseith Elementary School (4000119681) | — | 26/24 → 48/46% (p.12) |
| | Dunseith High School (4000119663) | — | 17/25 → 41/47% (p.14) |
| Mandaree | Mandaree Public School District (27036) | 6 goals, 6 metrics, 12 ratings | none |
| | Mandaree Elementary School (2703654591) | — | 20/11 → 44/37% (p.19) |
| | Mandaree High School (2703654593) | — | 35/16 → 54/40% (pp.20-21) |
| Warwick | Warwick Public School District (03029) | 5 goals, 25 metrics, 50 ratings | none |
| | Warwick Elementary School (0302992191) | — | 6/10 → 33/37% (p.27) |
| | Warwick Middle School (0302992192) | — | 12/8 → 38/35% (pp.28-29) |
| | Warwick High School (0302992193) | — | 15/31 → 40/52% (p.30) |

All annual targets include the alternate assessment (Combined), as each PDF section states.

**Comparisons.** No workbook metric of the five participants is compared with an ND Insights measure (`comparison/0`, `workbook: []`). Each reason is shown on the dashboard and in the PDF:
- **Not published by Insights:** the growth-or-proficiency metrics (per-student scale-score criteria) of all five.
- **Disengaged metrics:** Valley G3-M1, Drayton G4-M1 and Dunseith G6-M2 don't name the survey area, and their targets are text ("< 22% or within 7% State Avg", "< 18%", "< 15%").
- **"Engaged" isn't an Insights level:** Valley G5-M2, Drayton G4-M2.
- **Not imported:** graduation rate (Dunseith G3-M3) and chronic absenteeism.
- **Warwick:** its Insights-like metrics (emotionally disengaged, behaviorally committed, ELA/Math proficiency and novice, special-education novice) all have relative targets ("Inc 2-3%", "Dec 3-4%") with no baseline-year rule, and "Warwick School" doesn't say which scope is meant.

Only annual targets are compared, each with its own building and year. Every target year is 2025-26 or later, so all currently read "Not yet published".

**Data (dev database).**
- **Seeds:** `Seeds.run(dev_org, schools: <the 14 modules>)` created 589 records with 0 drift. A rerun created 0, left 589 unchanged and reported 0 drift.
- **Imports:** `mix nd_insights.import` for the 14 new IDs on all 17 files: 0 conflicts, 0 parse errors; name mismatches are the district short names only. A rerun created 0 and left 26,822 unchanged.
- **Check A (database vs CSV):** for all 16 school and district IDs plus 99999: 62,273 / 62,273 measures match, with 0 missing, 0 extra and 0 mismatched.

**Code.**
- **Seeds and config:** `Seeds.Participant`; four district modules generated from the sheets (`drayton.ex`, `dunseith.ex`, `mandaree.ex`, `warwick.ex`) and nine building modules; Valley `plan_start_year/0` and `comparison/0`; `Seeds.available_schools/0`; `Pilot` roster and `tab_slug/1`; and `pilot_institution_ids` in `config/config.exs`.
- **UI and PDF:** scope notes and building-page variants in `SchoolGoalsLive`, `Components` and `StateResultsComponents`; scope, guidance and source handling in `NdFirstSchoolPdf` and `nd_first_school.typ`.
- **Bug found and fixed:** duplicate DOM ids when building links appeared twice on a district page.

**Verification (November 8, 2026, Windows).**
- **Automated tests:** new `test/emisint_web/live/improvement/expansion_schools_test.exs` (11), with fixtures in `test/fixtures/nd_insights/expansion/`: Drayton district, elementary and high school and Valley rows, copied unchanged from the official 2024-25 Performance, Participation and Growth files and the Emotional Engagement file. It covers:
  - definitions and cited cells;
  - building-only targets;
  - seed reruns;
  - no workbook matches;
  - district versus building rows (Reading Approaching Proficiency 50%–54% district, 55%–59% elementary, 40%–49% high school);
  - building pages without goals or payment;
  - Valley exact values;
  - building-membership and other-organization isolation;
  - PDF data and real Imprintor PDFs.
- **Updated tests:** the roster ("Coming soon" removed), the pilot filter (now a synthetic `TEST000099` non-pilot school, `non_pilot_school!/1`) and the seeded-school list.
- **Results:** ND First, ND Insights, import and report suites 369/369. Full suite 561 tests, 157 failures: the legacy orphaned suites only, none in ND First files.
- **Server-rendered checks** (dev server, `admin@example.com`, 2024-25 Combined):
  - All 14 new dashboards and Fort Yates and Oberon return 200. Each shows only its own InstitutionID's rows, the right scope notes and links, building-only annual tables, district goals and "not configured" payment.
  - The student-group select is disabled where only all students are published (Drayton High, Mandaree High, Warwick Elementary and High). The latest-year links work (Warwick Elementary growth → 2023-2024).
  - `viewer@example.com` (Fort Yates only) and `admin@cornerstone-emo.edu` (another organization) were redirected on all 28 new dashboard and PDF URLs.
- **PDFs:** generated through `/school-goals/:slug/report.pdf` with the Windows-built Imprintor and viewed page by page via the Windows PDF API:
  - Valley 7 pages; districts 6–7 pages; buildings 3 pages each.
  - Fort Yates is still 7 pages and Oberon 6.
  - Fixed while checking: building reports showed a reporting period, a "[W]" workbook marker on the PDF source, and workbook-reference wording. These are now "Not applicable", unmarked and omitted.
- **Real browser: not done.** Headless Chrome still hangs on authenticated pages (one 45-second attempt on Valley's dashboard returned nothing). A manual desktop-browser check of every new dashboard is pending, as is Oberon's.

**Open items (not guessed).**
1. **Valley:**
   - The PDF's Measure 1 targets (79% / 65%, no completion date), the English Learner targets (20%–71%) and the chronic absenteeism goal (41% → 33%) are not stored.
   - G3-M1's survey area and compound target.
   - G5-M2's "Engaged".
   - Text targets ("> 50%", "n/a", "Created").
2. **Drayton:**
   - Goal titles: the sheet gives none, so the full goal text is the title.
   - G4-M1's survey area and whether its 25% baseline is district or building.
   - G4-M2's "Engaged".
   - G2-M3's "< 10%" baseline.
   - G4-M4's "Monitored".
   - The 75% "Related Learning Engagement Target" (PDF p.8; the PDF says category and calculation are unspecified).
3. **Dunseith:**
   - G1-M2/G2-M2's "50% K-6; 100% 7-12" campus-split target.
   - G4-M1's "70% @ Level 2+ / 3+".
   - G4-M2 has no baseline.
   - G6-M2's survey area.
   - Which graduation rate G3-M3 counts.
   - Elementary Measure 2 (writing, "20% improvement", unspecified per the PDF).
4. **Mandaree:**
   - G3-M1's "< 2.4" baseline.
   - G4-M1's "> 50%" / "> 80%" targets.
   - The PDF doesn't name the district (the Insights name is used).
5. **Warwick:**
   - The scope of "Warwick School".
   - A rule and baseline year for relative targets.
   - "Proficiency rate": Proficient, or Proficient or Advanced?
   - G2-M7's "Dec" target for a committed share.
   - Range and text targets (G2-M1, G2-M4, G5-M1, G2-M5).
6. **All district participants:**
   - Graduation targets (Drayton, Dunseith, Mandaree, Warwick high schools) aren't stored: graduation isn't in the imported datasets.
   - Several PDF sections assign years by an assumed sequence ("assume the same six-year sequence", "use the six values provided in chronological order"). The annual notes quote this.
7. **All five:** payment allocations; the "Target Check" 18-month column headings (flagged per metric); the review-year rules (item 27).

This section supersedes the earlier "Coming soon" descriptions in "Expansion: source audit and Oberon" (Shared school tabs) and the "deferred, not seeded by default" note for Valley.

### Expansion gaps: restored goals, Warwick scope, annual-year audit (November 8, 2026; uncommitted, pending review)

Supersedes the "not stored" items and the Warwick scope statement in "Expansion: remaining participants". Nothing was committed or pushed; there were no schema changes, migrations, database resets or Ash code generation.

**Sources re-read.**
- **PDF:** every page of `North Dakota - ND First Schools.pdf` relevant to the ten records, rendered via the Windows PDF API. Pages 1–3 (introduction) state no general year convention.
- **Workbook:** the School Directory, Overview and Evidence Tracker sheets, and all cell comments (reviewer narratives on the Sum '26 ratings).
- **User confirmations:** none of target years or of Warwick's scope is recorded in this plan or elsewhere in the repo.

**1. Goals restored** (`plan_targets/0` in each seed module, `Improvement.PlanTargets`).
- **Where they're kept:** in code with the other read-only definitions. There is no new table, so no migration.
- **Display:** an "Other plan targets" section (`#plan-targets`) on the dashboard and PDF. Each target shows its measure, baseline, targets exactly as written, a status and the source page. Values stay text and are never compared.
- **Statuses:** "Targets as stated in the source", "Year mapping unconfirmed", "Unresolved" (date or definition open) or "No numeric target in the source".
- **Results line:** each target also says why no result is shown, for example "Actual results unavailable: graduation rates are not in the imported ND Insights datasets. No comparison is made."

| Record | Restored targets (PDF location) | Status |
|---|---|---|
| Valley Middle | Measure 1 ELA 79% (baseline 38% in 2023–24) and Math 65% (24%), p.25 | Unresolved: no completion date |
| | English Learner proficiency 20/30/41/51/62/71% (2025–26 → 2030–31), p.26 | Year mapping unconfirmed |
| | Chronic absenteeism 41% (2023–24) → 33%, p.26 | Unresolved: no target year |
| Drayton Elementary | Engagement survey goal 75%, p.8 | Unresolved: category/calculation unspecified |
| Drayton High | Graduation four-year 82→90%, six-year 80→93%, p.10 | Year mapping unconfirmed |
| | Engagement survey goal 75%, p.11 | Unresolved |
| Dunseith Elementary | Writing improvement "20% improvement", p.12 | Unresolved: baseline/scale/meaning unspecified |
| Dunseith High | Graduation four-year 80→90%, five-year 77→92%, six-year 87→93%, p.14 | Year mapping unconfirmed |
| | English Learner Proficiency Growth 12→72%, p.15 | Unresolved: calculation undefined (and assumed years) |
| | College, Career and Military Readiness, p.15 | No numeric target |
| Mandaree Elementary | Kindergarten readiness (KRT), pp.19-20 | No numeric target |
| Mandaree High | Graduation four-year 71→90%, five-year 73→92%, six-year 66→93%, p.21 | Targets as stated |
| Warwick High | Graduation four-year 71→90%, five-year 76→92%, six-year 92→93%, pp.30-31 | Year mapping unconfirmed |

- **No omitted targets** for Fort Yates (p.17), Oberon (pp.23-24), Warwick Elementary and Middle (pp.27-29), or the district records.
- **Workbook metrics:** already stored in full; the workbook-to-seed generator round-trips the committed modules exactly.
- **Notes updated:** the old "not stored" report notes now point to "Other plan targets".

**2. Warwick scope: unresolved, labeled provisional** (`Seeds.Warwick.workbook_scope/0`, `Participant.provisional_scope?/1`).
- **Checked, none establishes the scope:**
  - Warwick Goals: "Warwick School will …", B2, B9, B19, B27 and B35.
  - School Directory row 5: "Warwick" / "Warwick Goals", no folder.
  - The Overview sheet.
  - Evidence Tracker rows 2–10: "Warwick"; rows 4 and 9 link "Mandaree826.key" and "Mandaree1012.key".
  - The cell comments (F3, F10, F20, F28, F36: "Warwick completed …").
- **Baselines against 2024-25 Insights rows fit no single scope** (context only, since the baseline years aren't stated):
  - ELA Novice 59% fits the district only.
  - Math Novice 75% and Emotional Disengaged 25.74% fit the elementary and middle schools.
  - Behavioral Committed 46.98% fits none.
- **Labeling:** the district dashboard shows `#workbook-scope-provisional` with the excerpt and evidence, and says the goals are "recorded on Warwick Public School District provisionally". Warwick building pages say "recorded provisionally on … whether they cover this building is not established". The PDFs carry the same wording and an amber "Workbook scope provisional" box.
- **Nothing scope-dependent:** no workbook comparison (`workbook: []`) and payment "Not configured".
- **Other districts:** Drayton, Dunseith and Mandaree are recorded as `:source_supported`, each citing its sheet text (B2) naming the district, "the district will …", and grades 3–10 spanning both buildings.

**3. Annual-target year audit** (`annual_years` in each comparison config; `ResultGoals.annual/3`).
- **Rule:** "assumed" mappings keep the targets visible, but year-specific comparison is off. Annual-table cells read "Not compared: year mapping unconfirmed (‹page›)" and the state table's Proficient-or-Advanced cell is gray "year mapping unconfirmed". Each annual section shows the mapping and excerpt (`#annual-year-mapping`).
- **Values:** every stored annual value was rechecked against the PDF; no value or year errors were found, so nothing was shifted.

| Record | Status | Source excerpt (location) |
|---|---|---|
| Fort Yates | stated | "Annual Proficiency Targets" listed by year, "2025–2026: ELA 25%; mathematics 11%." … "2030–2031: ELA 47%; mathematics 37%." (p.17) |
| Oberon | stated | "Displayed Long-Term Goal Period: 2018–2019 through 2023–2024"; targets listed by year (p.23) |
| Valley Middle | assumed | "Using the assumed 2025–2026 through 2030–2031 sequence:" (p.25) |
| Drayton Elementary | stated | "Annual Proficiency Targets – All Students", listed by year (p.7) |
| Drayton High | assumed | "The annual targets below use the six values provided in chronological order, beginning with 2025–2026." (p.9) |
| Dunseith Elementary | assumed | "The annual targets below assume the same six-year sequence as the previous schools." (p.12) |
| Dunseith High | assumed | same sentence (p.13) |
| Mandaree Elementary | stated | targets listed by year (p.19) |
| Mandaree High | stated | targets listed by year (pp.20-21) |
| Warwick Elementary / Middle / High | assumed | "Using the assumed 2025–2026 through 2030–2031 sequence:" (pp.27, 28, 30) |

Fort Yates and Oberon are unchanged: both are "stated", and Oberon's 2021-22 to 2023-24 comparisons remain.

**Verification (November 8, 2026, Windows).**
- **Automated tests:** new `test/emisint_web/live/improvement/expansion_gaps_test.exs` (9) covers:
  - the restored targets per school, values as written;
  - Valley and building dashboards showing them with no verdict;
  - Warwick provisional on the district, buildings and PDF, with no comparison or payment, and Drayton not provisional;
  - an assumed mapping giving `:year_unconfirmed` on Valley's real 2024-25 Reading row, where the same row and target give "Meets" under a stated mapping (also in the state-table cell);
  - each school's mapping status;
  - dashboard and PDF labels;
  - real Imprintor PDFs.
- **Updated tests:** three earlier assertions now expect "year mapping unconfirmed" (Valley, Drayton High).
- **Results:** ND First, ND Insights, import and report suites 378/378. Full suite 570 tests, 157 failures: the legacy suites only, none in ND First files.
- **Server-rendered checks:**
  - 13 dashboards and PDFs return 200 with the expected plan-target counts, provisional labels (Warwick only) and year-mapping status.
  - Fort Yates is still 7 pages and Oberon 6.
  - The server was restarted once: line-ending normalization touched `config/config.exs`.
- **PDFs viewed:**
  - Dunseith High, Valley and the Warwick district page by page, plus contact sheets for Warwick High, Mandaree High, Drayton High and Oberon.
  - Fixed while checking: stale "not stored" notes in seven modules, and annual notes on assumed-year schools that still said targets "are compared".
- **Real browser: not done** (the headless-Chrome hang is unresolved). Manual checks of all dashboards are pending.

**Decisions needed (exact sources).**
1. **Warwick scope:** "Warwick School will …" (Warwick Goals!B2, B9, B19, B27, B35). District, or which building?
2. **Assumed year sequences:**
   - Valley p.25 and Warwick pp.27/28/30: "Using the assumed 2025–2026 through 2030–2031 sequence:"
   - Drayton High p.9: "use the six values provided in chronological order, beginning with 2025–2026"
   - Dunseith pp.12/13: "assume the same six-year sequence as the previous schools"
   
   Confirm the years to enable comparisons.
3. **Valley Measure 1:** "These targets are listed in the 2025–2026 strategy map; a separate target completion date is not specified." (p.25) Which year, and which assessment (the Measure 1 metric doesn't mention the alternate assessment)?
4. **Valley chronic absenteeism:** "Baseline: 41% in 2023–2024. Target: 33%." (p.26) The target year is not given.
5. **Drayton engagement 75%:**
   - p.8: "without specifying the survey category or calculation"
   - p.11: "does not specify the survey response category or calculation used for this target"
6. **Dunseith writing:** "does not specify the baseline, rubric scoring scale, or whether “20%” means relative improvement or a percentage-point increase" (p.12).
7. **Dunseith English Learner:** "confirm whether the graph measures students meeting their growth targets or students attaining proficiency" (p.15).
8. **Data sources** for graduation, English Learner, attendance, writing, readiness and kindergarten-readiness results, if those comparisons are wanted. None is in the imported datasets.

### User confirmation: annual target years (recorded November 8, 2026)

**User confirmation.** The user stated that the graph-year mappings had already been confirmed by them, and that the seven sequences disabled above use the confirmed **2025–2026 through 2030–2031** mapping, in order. This supersedes the "assumed" status in "Expansion gaps … 3. Annual-target year audit" and decision 2 there.

- **Records changed (`annual_years.status: :confirmed`, with a `confirmation` note; the source excerpt is kept):**
  - Valley Middle (p.25);
  - Drayton High (p.9);
  - Dunseith Elementary (p.12) and Dunseith High (p.13);
  - Warwick Elementary, Middle and High (pp.27, 28, 30).
- **Comparisons restored:** each annual target is compared only with the published result of its own school year, as for stated mappings (`ResultGoals.annual/3`). A 2025-26 target is never compared with 2024-25 results. Every confirmed target year is 2025-26 or later, so all currently read "Not yet published".
- **Labels:** the dashboard and PDF say "Year mapping confirmed by the user: the targets are 2025–2026 through 2030–2031, in order (recorded November 8, 2026)", followed by the source wording.
- **Same-section series:** the graduation series (Drayton High, Dunseith High, Warwick High) and Valley's English Learner series use the same year sequence as their section's annual targets. They now read "Years confirmed by the user". They're still not compared, since there's no imported data.
- **Unchanged:**
  - Undated or undefined targets stay unresolved: Valley Measure 1 and chronic absenteeism, both Drayton engagement goals, Dunseith writing, and Dunseith English Learner (calculation undefined).
  - Fort Yates, Oberon, Drayton Elementary and Mandaree stay "stated".
  - The `:assumed` handling remains in code for any future unconfirmed sequence.
- **Verification:**
  - **Automated tests:** `expansion_gaps_test.exs` (10 tests, one added) covers the seven confirmed mappings with the source excerpt kept; a same-year comparison on Valley's real 2024-25 row ("Meets"); and no comparison of a 2025-26 target with 2024-25 results. It still covers the assumed-mapping behavior for any future unconfirmed sequence.
  - **Results:** ND First, ND Insights, import and report suites 386/386. Full suite 578 tests, 157 failures: legacy only, none in ND First files.
  - **Server-rendered checks:** the 7 confirmed pages show `data-year-mapping="confirmed"` and no "year mapping unconfirmed" cell. Valley's PDF page 5 was viewed.

### ND FIRST navigation: one tab per participant (November 8, 2026; uncommitted, pending review)

Supersedes the tab descriptions in "Expansion: source audit and Oberon" (Shared school tabs) and "Expansion: remaining participants". URLs, permissions, data, goals and PDFs are unchanged.

- **Main tabs** (`Pilot.tabs/1`, `Components.school_tabs/1`):
  - **Order:** one tab per participant: Fort Yates, Oberon, Valley Middle, Drayton, Dunseith, Mandaree, Warwick. Cannon Ball stays deferred and unlisted, and buildings never get a main tab.
  - **Destination:** a tab opens the participant's main record (the school, or the district for district participants).
  - **Access:** tabs show only destinations the signed-in user can read (`Pilot.readable_slugs/1`, one `Dashboard.list_schools/2` read under the school policies).
    - A participant with nothing readable has no tab.
    - When only a building is readable (e.g. a Drayton Elementary-only member), the tab opens that building.
  - **Active tab:** the participant's tab stays highlighted (`aria-current="page"`) on any of its buildings (`Pilot.tab_slug/1`).
- **Participant navigation** (`Pilot.participant_nav/2`, `Components.participant_nav/1`, `#participant-nav`):
  - **Where:** on the district dashboard and every building dashboard of Drayton, Dunseith, Mandaree and Warwick.
  - **Items:** "District overview", then "Elementary School", "Middle School" or "High School", in plan order. The current page is highlighted, and only readable pages are listed.
  - **Warwick:** the navigation carries a "Workbook scope provisional" badge on the district and every building.
  - **Single-building participants:** no participant navigation.
- **Landing page** (`/school-goals`):
  - Cards are grouped by participant in tab order.
  - Each district card lists its readable buildings (the same `school-<slug>` links as before).
  - Warwick's card shows the provisional badge.
- **Scope notes:** links to records the user can't read are now plain names (`data-readable="false"`), with no "(no access)" text.
- **Verification (November 8, 2026):**
  - **Automated tests:** new `test/emisint_web/live/improvement/navigation_test.exs` (7) covers:
    - tab order and labels, with no building tabs;
    - landing groups;
    - single-school active states;
    - each district's navigation, with District overview current;
    - a direct link to each of the 9 buildings, with the participant tab and the building current (exactly one tab and one page);
    - Warwick's badge on all four pages;
    - the Fort Yates-only viewer (one tab, no participant navigation, building URLs redirect);
    - a building-only member (the tab opens the building; only that page is listed).
  - **Updated tests:** the Oberon tab test (other participants' tabs are hidden in an organization without them) and the building-permission test (no "(no access)" text).
  - **Results:** ND First, ND Insights, import and report suites pass. Full suite 577 tests, 157 failures: the legacy suites only, none in ND First files.
  - **Load note:** one earlier full run, made while the dev server was also being exercised, took 648 s and had 9 extra failures, all 60-second `ExUnit.TimeoutError`s in legacy suites. Rerun alone, it took 70 s with the usual 157.
  - **Server-rendered checks** on the dev server:
    - **`admin@example.com`:** all 16 pages show the 7 tabs in order, the participant tab current and the right navigation item current; the Warwick badge appears on its 4 pages only.
    - **`viewer@example.com` (Fort Yates only):** one tab; the 15 other URLs redirect.
  - **Real browser: pending** (headless-Chrome hang unresolved).

### Goal-comparison colors beyond Fort Yates (November 8, 2026; uncommitted, pending review)

Audit of why only Fort Yates showed goal colors, and the fixes. Fort Yates's behavior (numeric targets, demo assumptions, grade references) is unchanged, and no Fort Yates target or assumption is applied to another school.

- **Causes found:**
  - **Text targets:** any target not stored as a number was gray (`:target_not_comparable`), including "< 18%", "> 35%" and ranges such as "55-60%" (`:target_is_range`).
  - **Oberon achievement:** gray (`:assessment_type_unconfirmed`) because the workbook doesn't name the assessment.
  - **Oberon engagement:** gray, from the range targets and an unverified survey population.
  - **Valley, Drayton, Dunseith, Mandaree, Warwick:** `workbook: []`, so no comparison was even attempted.
  - **Buildings:** annual targets only (2025-26 onward), with no matching results in the imported data; unchanged.
- **Rules added** (`ResultGoals.target_spec/2`, `classify_bound/3`, `classify_band/4`):
  - **Inequality:** strict, so an equal value doesn't meet "< 18%"; meets when the whole published value satisfies it, misses when none of it does, otherwise overlaps.
  - **Range:** a **dashboard comparison convention, not a source-confirmed scoring rule**, since the sources don't define when a range target is met. Only verdicts that hold whichever end counts are given: meets beyond the far end, misses wholly short of the near end, otherwise overlaps. The cells, the section note and the methodology say so.
  - **Compound** ("< 22% or within 7% State Avg"): meets through its inequality; otherwise gray (`:compound_target`), because the other condition isn't defined in the sources.
  - **Empty or "n/a" target:** gray (`:no_target`). Relative ("Dec 2-3%"), qualified ("70% @ Level 2+") or split ("50% K-6; 100% 7-12") targets stay gray (`:target_not_comparable`).
  - **Percent text:** must carry "%" (stored as 0–1).
- **Candidates** (shown in each cell's explanation and the section note; never labeled as assumed): `candidates` (`%{code => evidence}`) marks a mapping whose survey category or population is only inferred, e.g. from a baseline match. It is a candidate to investigate, not a confirmation. Its value and target are shown gray (`:mapping_unconfirmed`, "Gray: candidate mapping, awaiting confirmation") with the evidence, never a verdict. The earlier `engagement_basis` mechanism is removed (see the Oberon engagement source check).
- **Correction (November 8, 2026, per user review):** the first pass treated two kinds of evidence as confirmation. Both are reversed.
  - **Valley G3-M1 and Drayton G4-M1:** the baseline matches were treated as confirming the survey category. Both are now documented candidates with their verdicts disabled.
  - **Oberon achievement:** identical Combined and Standard values were treated as settling which assessment the workbook targets count. They don't establish the workbook's definition, so the rule (`assessment_type_rule: :identical`) is removed. Oberon's workbook achievement comparisons are gray, "awaiting assessment confirmation"; its confirmed annual comparisons are unchanged.
  - **Label:** annual targets with no matching row now say "No matching results in the imported data" instead of "Not yet published", because publication availability wasn't independently verified.
- **Oberon engagement source check (November 9, 2026, per user review):** the sources were checked for an explicit statement of the survey population behind G4-M1..M3.
  - **Workbook** ("ND First School MOU Goal Overview.xlsx", sheet "Oberon Goals", rows 25–29): the metric wording names the Emotional category ("% of students reporting as Emotionally Committed / Compliant / Disengaged"). It gives no survey name, year, grades or population.
  - **Plan** (North Dakota - ND First Schools.pdf pp.23–24, Oberon's section): achievement, annual targets, progress monitoring and initiatives only. No engagement survey or population is mentioned.
  - **Result:** the population is inferred only from matching baselines. G4-M1/G4-M2 (45-49%, 40-44%) equal the 2024-25 published Emotional Committed and Compliant values; G4-M3's 6-10% doesn't match the published 10%–14%. So G4-M1..M3 are now candidates with no verdict, and `engagement_basis` is removed. The range convention (`classify_band/4`) is kept, unit-tested, for when the population is confirmed.
- **Accidental formatting cleanup (November 9, 2026):** an unscoped `mix format` (run while applying the correction) reformatted tracked files outside the change.
  - **Backups first:** in the session scratchpad `format_backup/`: the full working-tree diff, the accidental diffs (`accidental_57.diff`, `accidental_2_more.diff`), tar archives of the affected files and the prior `git status`.
  - **Pre-format state established, per file:** the session began with a clean tree. The session transcript records no Edit/Write call, sed, script or glob command touching these files before the format run, and no other unscoped `mix format`. The Mac ZIP (`emisint.zip`) copies equal HEAD. So each file's pre-format content was HEAD's.
  - **Reversal:** only the accidental changes were reversed, with `git apply -R` of the recorded diffs; the checkout's CRLF line endings were then restored.
    - **Scope:** the 57 files outside ND First, plus 2 ND files I never edited (`nd_insights_import_live.ex`, `metric_history_live.ex`; whitespace-only HEEx changes).
    - **Check:** all 59 now match HEAD's checkout byte for byte.
    - **Kept:** formatting of files I edited for ND First.
- **Per-school result:**

  | School | Comparisons with a verdict | Shown without a verdict, or uncompared — exact decision or data needed |
  | :-- | :-- | :-- |
  | Fort Yates | Unchanged (G2/G3 achievement, G2-M3/G3-M3 growth percentile, G4-M2..M4 engagement; annual targets) | — |
  | Oberon | Annual targets 2021-22 to 2023-24 (2018-19 to 2020-21: no result imported) | G1-M1/G2-M1 and G1-M2/G2-M2: gray, awaiting confirmation of which assessment (Combined, Standard or Alternate) the workbook targets count. Caveat for then: the workbook achievement baselines don't match the published values (ELA Novice 36% vs 50%–79%). The imported 2024-25 data has no achievement levels. G4-M1..M3 Emotional Committed/Compliant/Disengaged: candidates, gray. No source states the survey population; it is inferred from baselines (G4-M1/M2 match 2024-25; G4-M3 doesn't). Needs confirmation of the survey population; the range targets would then use the dashboard convention. |
  | Valley Middle | Annual targets (2025-26+; no matching results in the imported data) | G3-M1 → Overall Disengaged: candidate, gray. Evidence: baselines 28%/24%/24% equal the published 2022-23..2024-25 Overall values. Needs confirmation of the survey category; then also the 18-month "n/a" target and the meaning of "within 7% State Avg". G5-M2 "Engaged or Committed": unmapped until "Engaged" is defined. |
  | Drayton (district) | — | G4-M1 → district Overall Disengaged: candidate, gray. Evidence: baseline 25% lies in 25%–29% for 2023-24 and 2024-25. Needs confirmation of the survey category and whether the baseline is a district figure; the 18-month target is empty. G4-M2 "Engaged": unmapped until defined. |
  | Dunseith (district) | None | G6-M2's survey area: baseline 20% matches no published area (2022-23..2024-25 Overall 18%, Behavioral 13%–16%, Cognitive 10%–13%, Emotional 26%–30%); its "< 15%" target is comparable once the area is confirmed. Graduation rate (G3-M3) isn't in the imported data. |
  | Mandaree (district) | None | No workbook metric has an Insights counterpart (growth-or-proficiency criteria, Likert and rubric scores, pacing guides). |
  | Warwick (district) | None | Relative targets ("Inc 2-3%", "Dec 2-3%") have no base year or points-versus-percent rule (G2-M6, G2-M7, G3-M1, G3-M2, G4-M1, G4-M2, G5-M3, G5-M4); workbook scope still provisional. |
  | 9 buildings | Annual Proficient-or-Advanced targets for their own years (2025-26 onward) | No matching results in the imported data for 2025-26 onward (publication availability not independently verified). The district's workbook goals aren't copied to buildings. |

- **Verification (November 9, 2026, after the Oberon engagement change and the formatting cleanup):**
  - **Automated tests:** 398 ND First, ND Insights and report tests pass.
    - **`text_target_comparisons_test.exs`:** parsing; strict inequality; candidate mappings (gray, evidence shown, target still parsed); unmapped "Engaged" metrics; unsupported participants; buildings; Fort Yates configuration.
    - **Oberon unit tests:** achievement gray "awaiting assessment confirmation", even with identical Combined and Standard rows; G4-M1..M3 candidates (gray, evidence cites pp.23-24 and the baseline match); `classify_band/4` edge cases.
    - **`oberon_live_test.exs`:** the Novice cell is gray, awaiting assessment confirmation; the Emotional cells are gray candidates at both checkpoints, with no colored engagement cell.
    - **`expansion_schools_test.exs`:** the only listed mappings are candidates.
    - **Label tests:** updated to "No matching results in the imported data".
  - **Server-rendered checks:** HTTP 200 on the dev server.
    - **Oberon 2023-24, 18-month:** workbook achievement gray ×2 ("awaiting assessment confirmation"); engagement gray ×3 ("candidate mapping, awaiting confirmation"); 2 annual overlaps.
    - **Oberon 2024-25, 36-month:** engagement gray ×3, candidates.
    - **Valley 2020-21 and Drayton 2024-25 (36-month):** one gray candidate cell each, "candidate mapping, awaiting confirmation".
    - **Valley and Drayton Elementary:** annual cells read "No matching results in the imported data".
  - **PDFs:** generated through Imprintor for Oberon, Valley, Drayton, Dunseith, Fort Yates and Drayton Elementary; Oberon page 4 was rendered and inspected. Labels match the dashboards, and no PDF contains "Not yet published".
  - **Real browser:** pending.

### ND FIRST portfolio dashboard on `/school-goals` (November 9, 2026; uncommitted, pending review)

Requested for Ram: a summary of all participants before a school is selected, following the first two sheets of "ND First School MOU Goal Overview.xlsx". Individual dashboards, navigation (tabs, participant cards) and comparison rules are unchanged.

- **Source sheets.** Workbook order: "School Directory" (hidden), **"Goals Dashboard"**, **"Performance-Based Payment"**, "Example School", the school sheets, "Evidence Tracker", and "Overview" (hidden). The first two visible sheets are the requirements; the hidden "School Directory" supplies only each row's "Group". All three were read in full from the sheet XML, including formulas, merges, conditional formats and hyperlinks.
- **Implemented** (`Emisint.Improvement.Portfolio`, `EmisintWeb.Improvement.PortfolioComponents`, `Dashboard.current_ratings/2`):
  - **Rows:** one per participant in the workbook's row order (Fort Yates, Solen, Oberon, Warwick, Mandaree, Dunseith, Drayton, Valley MS), each linked to its dashboard, as the workbook's names link to their sheets. Each row is the participant's main record (district for district participants). Building records are never rows and add nothing.
  - **Goals Dashboard columns:**
    - **Metric counts:** `COUNTIF` by category.
    - **Spr '26 / Sum '26 / Fal '26:** per-category `AVERAGEIF` of the current seasonal implementation ratings.
    - **18m Check:** the same, on the formal 18-month review ratings.
    - **Win '27 – Spr '28:** a single `AVERAGE` per period. These columns are in an expandable "Later periods" table.
    - **36m Check (S–V):** the workbook gives headings only. The checks use the 18m Check formula; the weighted scores use the headed 30% / 70% weights, which equal the confirmed 36-month weights.
    - **AVERAGE row:** over the shown participants, with coverage.
    - **Rubric key and colors:** the workbook's conditional-format bands (≤0.49, 0.50–1.49, 1.50–2.49, ≥2.5).
  - **Performance-Based Payment columns:**
    - **C–H by the sheet's formulas:** score, ×70%, score, ×30%, overall only when both exist, ÷3.
    - **Payout column:** the existing payment estimate (`Payment.summary/3`): "Awaiting review" until every review rating is recorded, "Not configured" without terms.
  - **Missing data:** shown as "—" (`data-missing`), never 0. Partial coverage is shown as e.g. "13/16".
  - **Access:** every read runs as the user. A member sees only their participants, and the AVERAGE row covers only those. A building-only member gets the participant row without figures, linked to the readable building. Other organizations see nothing.
  - **Solen:** superseded November 9, 2026: the "Solen" row is now the Cannon Ball participant (see "Cannon Ball participant").  _(Originally listed as "Not configured" for organization admins only.)_
- **Deliberately different from the workbook, or not reproduced:**
  - **AVERAGE row (C13:L13):** the workbook's includes Solen (C13 = 8.5), and E13:L13 also include the "Example School" row. Ours averages the configured participants shown (originally C = 9.00 over 7; with Cannon Ball, C = 8.50 over 8, equal to the workbook's C13).
  - **Payout ("18-month payout (up to $70,000)" = % × $70,000, blank at 0):** the app's confirmed estimate rule uses each plan's 18-month allocation (Fort Yates $35,000, provisional; others not configured). It requires complete review ratings and never blanks $0. The sheet has no total row, so no portfolio payment total is shown.
  - **Not shown:** the hidden "Tab Name" column. Also not shown: the School Directory's Drive Folder URL, School Spreadsheet URL, Last Synced and Sync Status (Google sync metadata, mostly errors). Also the "Example School" row, Solen's cached figures (not imported), and the 36-month payment (the payment sheet covers the 18-month review only; each school dashboard has both checkpoints).
- **Verification (November 9, 2026):**
  - **Workbook check:** every participant's C–H values (Spr '26 and Sum '26) match the workbook's cached "Goals Dashboard" values, checked on the dev database and in tests.
    - Fort Yates: 8 / 10 metrics; Spr '26 1.25 / 1.6; Sum '26 1.375 / 1.6.
    - Oberon: 9 / 12; 1 / 1.583; 1.667 / 1.917.
    - Warwick: 14 / 11; 1.857 / 1.636; 1.929 / 2.
    - Mandaree: 3 / 3; 1 / 3; 2 / 3.
    - Dunseith: 7 / 9; 1.833 / 1.889; 2.167 / 1.889.
    - Drayton: 6 / 7; 1.333 / 2.143; 1.667 / 2.143.
    - Valley MS: 16 / 10; 1.462 / 1.4; 2.125 / 1.8.
    - No Fal '26 or review ratings exist yet, so those columns show "—".
  - **Automated tests:** `test/emisint/improvement/portfolio_test.exs` (10) and `test/emisint_web/live/improvement/portfolio_live_test.exs` (3) cover workbook values, AVERAGEIF exclusions, the AVERAGE row, no building rows or double counting, Solen visibility, missing data, partial and complete review ratings (2.4 weighted, 80%, $28,000.00 estimate), and access isolation (single-school member, building-only member, other organization). All 411 ND First, ND Insights and report tests pass.
  - **Server-rendered checks:** HTTP 200 on the dev server.
    - **`admin@example.com`:** all 8 rows; values match the workbook to two decimals.
    - **`viewer@example.com` (Fort Yates only):** only the Fort Yates row.
  - **Real browser:** pending.

### Cannon Ball participant (November 9, 2026; uncommitted, pending review)

- **User confirmation (recorded November 9, 2026):** “the workbook’s ‘Solen’ sheet represents the Cannon Ball ND FIRST participant.” The confirmation maps the workbook participant only; it does not authorize using Solen district or another building's state results.
- **InstitutionID, verified against the sources:**
  - **ND Insights files:** every one of the 17 imported files (2021-22 – 2024-25 Performance, Participation and Growth; the five Engagement files) publishes "Cannon Ball Elementary School" as **4300312781**, district "Solen Public School District" (**43003**), with one name per ID.
  - **Same district, not used:** Solen High School (**4300380363**) and the district are separate rows and are never imported for Cannon Ball.
  - **PDF:** pp.4–6 head the plan "Cannon Ball Elementary School, Solen Public School District"; p.1 lists "Cannon Ball" as an ND First school.
- **Record:** `Seeds.CannonBall` (`lib/emisint/improvement/seeds/cannon_ball.ex`), a single-building participant: Cannon Ball Elementary School, slug `cannon-ball-elementary`, grade span not stated in the sources (nil).
  - **How it was generated:** from the "Solen Goals" sheet, with the same generator as the other participants. Every value cites its cell.
  - **Goals and metrics:** 7 goals; 18 metrics (5 Systems, 13 Student Outcomes, matching Goals Dashboard!C6:D6) with baselines and 18-/36-month targets.
  - **Ratings:** 36 Spr '26 / Sum '26 ratings (`workbook_ratings/0`).
  - **Kept as written:** G5-M1's date cells (D30, H30, P30) are flagged `:source_value_is_date`. G7-M2's "< 10%" is `:value_as_text`. G2-M1–M3 have no baseline (missing, not zero). Goals 2–7's 18-month column is headed "Target Check" (flagged).
  - **Annual targets:** PDF p.4 "Annual Proficiency Targets – All Students", 2025–2026 (ELA 13%, Math 7%) through 2030–2031 (38%, 34%), each with its stated year (`annual_years: :stated`), ND A+ or NDAA (compared with Combined). No other plan targets.
  - **Payment:** $70,000 cap as on the "Performance-Based Payment" sheet. Allocations are not set (no source gives them), so the estimate is "Not configured".
- **Scope gap:** the sheet's goals are written for Solen Public School District and its schools (Cannon Ball Elementary, Solen Jr. High, Solen High School). Shown in the dashboard and PDF notes.
- **Wiring:**
  - **Config:** `pilot_institution_ids` + "4300312781".
  - **Roster:** `Seeds.available_schools/0` + `CannonBall`. The main tab "Cannon Ball" is last, after the previously confirmed order.
  - **Portfolio:** the workbook's "Solen" row is now the Cannon Ball participant row (labeled "Workbook row “Solen”"), in its workbook position, replacing the placeholder. There are still 8 rows, not 9.
  - **Unchanged features:** dashboard, filters, data entry, history, PDF and permissions are the existing shared ones.
- **Comparisons:**
  - **Annual targets:** compared with Cannon Ball's own result for the same year. All targets are 2025-26 or later, so they currently read "No matching results in the imported data".
  - **Workbook metrics: none matched**, because these definition gaps remain:
    - **Grade bands:** the Reading and Novice metrics count grades 3-5 and 6-8. Insights publishes per grade and All Grades only, and ranges can't be combined without a rule.
    - **Grade 10:** G1-M3, G1-M6, G2-M3 and G2-M6 cover Grade 10, which Cannon Ball Elementary doesn't have. Solen High School's results are not substituted.
    - **Proficiency:** "demonstrate proficiency" doesn't say Proficient alone or Proficient or Advanced.
    - **Growth:** "expected annual growth" isn't an Insights growth category.
    - **Local measures:** G7-M1 and the Systems metrics.
    - **Engagement:** the sheet has no engagement metric.
- **Dev database (no reset):**
  - **Seeds:** `Seeds.run` for `CannonBall` created 86 records (school, plan, 7 goals, 18 metrics, 11 periods, 12 annual targets, 36 ratings). The rerun created nothing (86 unchanged, 0 drift).
  - **ND Insights import:** `mix nd_insights.import --institution-id 4300312781` on all 17 reference files created 1,694 measures, with 0 conflicts, parse errors or name mismatches. The rerun created nothing.
  - **Independent check:** CSVs vs database for 4300312781: 1,694/1,694 match, with 0 missing, 0 extra and 0 value mismatches.
  - **Missing data:** Cannon Ball's rows have no suppressed cells. Missing grades and years (e.g. grade 8 achievement in 2024-25, grade 7 in 2022-23) are absent rows and show "Not published", never 0.
- **Portfolio values:** Cannon Ball counts 5 / 13; Spr '26 1.2 / 1.923; Sum '26 1.4 / 1.923, matching Goals Dashboard!C6:H6.
  - **AVERAGE row:** now covers 8 participants. C = 8.5 equals the workbook's C13. The workbook's E13 (1.353927554) is reproduced by adding its Example School row (1.25) to our 8-participant mean.
- **Verification (November 9, 2026):**
  - **Automated tests:**
    - **New:** `test/emisint_web/live/improvement/cannon_ball_test.exs` (11) covers the mapping and InstitutionID, the workbook definitions and ratings, the PDF annual targets, storage of only 4300312781 (with Solen district/high rows in the fixture), rerun safety with a manual rating kept, the dashboard, data entry and history, the PDF, the portfolio values and AVERAGE row, and access isolation.
    - **Fixtures:** `test/fixtures/nd_insights/cannon_ball/` (rows copied unchanged).
    - **Updated:** the portfolio tests (Solen placeholder → Cannon Ball, 8 participants), the navigation test (Cannon Ball tab last) and the seeds test (Cannon Ball ID).
    - **Results:** all 421 ND First, ND Insights and report tests pass.
  - **Server-rendered checks:** HTTP 200 on the restarted dev server.
    - **`admin@example.com`:** 8 portfolio rows, Cannon Ball in the Solen position with the workbook values. The Cannon Ball dashboard shows 18 metrics and 12 annual targets.
    - **`viewer@example.com`:** only Fort Yates; Cannon Ball's page redirects.
    - **PDF:** `/school-goals/cannon-ball-elementary/report.pdf` (6 pages) was rendered and inspected: header ND 4300312781, Sum '26 1.4 / 1.92, workbook cells cited, payment "Not configured", and its own 2024-25 results.
  - **Real browser:** pending.

### Phase 3: 18-month review + payment

- [x] **17.** Formal review ratings: `ImplementationRating.:record_review` (review periods only; contributor policy, `RatingShape` validation and `:correct` history shared with seasonal ratings). No separate `ReviewRating` resource; the `:reviewer` membership role is still unused.
- [x] **18.** Review entry UI: at a review period the update panel shows "Formal review rating (0–3)" beside the actual-result form, saved separately.
- [x] **19.** Estimated payment (provisional cap and split): payment section and card on the dashboard, matching PDF section, `PaymentEstimate` recording for org admins. Tests: `test/emisint/improvement/payment_estimate_test.exs` (both weightings, zero/full/partial, missing and N/A, allocation cap, half-up rounding, separate category averages, seasonal exclusion, terms validation and policy, preserved assumptions, corrections) plus LiveView and PDF tests. Stays provisional until the actual terms are confirmed.

### Phase 4: expansion (deferred until the Fort Yates experience is approved)

- [x] **20.** Model multi-building participants and add Drayton, Dunseith, Mandaree, Valley Middle School and Warwick from their own sheets and goals (Oberon done November 4, 2026; the rest November 8, 2026). All pending individual review; Cannon Ball deferred. See "Expansion: remaining participants". The open items listed there remain unresolved.
- [ ] **21.** `PortfolioLive` (`/nd-first`).

---

## Unresolved items (recorded, not guessed)

1. **`Ft Yates Goals!P7` = 90 and `P16` = 80** (G1-M4 and G2-M4 36-month targets), in `General` format while other targets are decimals. The originals are kept in `source_values`, `target_36m` is left **unset**, and the metrics are flagged `:target_36m_needs_confirmation`. They are excluded from calculations.
2. **Goal 4 column I is headed "Target Check"** (`I26`), while Goals 1–3 use "18-Month Review Rating" (`I3`, `I12`, `I19`). The payment sheet averages the whole of `'Ft Yates Goals'!I:I` by the category in column A (`Performance-Based Payment!C4`, `E4`), so Goal 4's rows 27–30 would count. (Correction: an earlier revision said the formula reads `I27:I30` directly; it uses whole-column `AVERAGEIF`.) The dashboard shows this as one expandable note under the Goal 4 heading; the metrics keep `:review_18m_column_heading_unconfirmed`.
3. **Column Q "Target Check"** (36-month) has 3/2/1/0/N/A validation with an undefined meaning.
4. **Review dates and reviewer assignments** are unknown.
5. **Solen vs Cannon Ball:** resolved November 9, 2026 — the user confirmed that the workbook's "Solen" sheet represents the Cannon Ball participant (see "Cannon Ball participant"). Its record is Cannon Ball Elementary School (InstitutionID 4300312781); Solen district and Solen High School results are never substituted.
6. **Weight labels, resolved October 23:** the weights differ by checkpoint. The 18-month review is Systems 70% / Outcomes 30% (the payment sheet), and the 36-month review is Systems 30% / Outcomes 70% (the "Goals Dashboard" `T2`/`V2` labels). How the $70,000 maximum applies across the checkpoints is still not confirmed. Ram authorized a best-estimate rule on November 1, 2026; the $70,000 total and equal $35,000 split are our selected provisional assumptions, not terms he specified (see Payment).
7. The workbook hides a $0 payout as blank. We show $0.00.
8. Payout rounding is not specified by the sources. Provisional: half up to cents, after capping.
9. The average-score color key (`W5:X8`) has a 0.49–0.50 gap. No color bands until confirmed.
10. **Production owning organization:** to be supplied explicitly at seed time.
11. Baseline years and sources for the workbook metrics are unknown. Workbook "Proficient" ≠ PDF "Proficient or Advanced".
12. ~~Insights CSV verification and the Growth Rate / Engagement Survey schemas are pending (Task 13).~~ Done; see Phase 2. Open source questions are items 17–26.
13. **UNRESOLVED HAZARD — teammate dev migration (SSS):** `20260701032125_migrate_resources1_dev.exs` and its three `_dev.json` snapshots are still a `--dev` migration. **Any non-`--dev` codegen run with pending changes rolls it back** — including `--dry-run` and `--snapshots-only` (AshPostgres `MigrationGenerator` calls `remove_dev_migrations/4` before checking those flags): it runs the migration's `down` against the configured database and deletes the files. This happened on November 1, 2026 (see "Provisional payment rule"). Until the owner converts it:
    - Never run `mix ash.codegen <name>`, `--dry-run` or `--snapshots-only` in this repo against a database with data. `--check` is safe (it exits before removing anything) but always fails while the `_dev` migration exists, because non-dev mode ignores `_dev.json` snapshots.
    - To generate or verify migrations for other resources, use an isolated copy of the project with the `_dev` migration file removed (keep its snapshots) and `config/dev.exs` pointing at a non-existent database; copy back only the snapshots/migration for your own resources and hand-review them. This is how `20261101180000_add_provisional_payment_estimates.exs` and its two snapshots were verified.
    - The owner can convert it without a rollback by renaming the migration (dropping `_dev`, same version) and its snapshots to `20260701032125.json`, then confirming `mix ash.codegen --check` passes; or by running the named `mix ash.codegen` only against a disposable database and re-applying.
14. **Stale `schools` snapshots:** `priv/resource_snapshots/repo/schools/20260225234912.json` and `20260317014725.json` describe the old table dropped by `cleanup_removed_resources`. The new snapshot supersedes them, but they could be removed in a dedicated cleanup.
15. Timestamps are displayed in UTC. The app's per-session timezone cookie is not used yet.
16. **Implementation step wording is missing from the sources.**
    - The workbook stores only the step counts per period (`Ft Yates Goals!D2` and the following columns). `C1` points to "the linked action-planning and progress-monitoring document", whose link (`B1`) is "TBD".
    - The Evidence Tracker has no Fort Yates rows.
    - PDF p.17 lists "Supporting Academic Initiatives" for the annual goals, not per-period steps for the four workbook goals.
    - To show step text, we need that document (or its URL for `GoalPlan.progress_doc_url`).
    - Related: the workbook has threaded reviewer comments on the Sum '26 goal headers (`F3`, `F12`, `F19`, `F26`). These are not imported.

**ND Insights source questions (Phase 2):**

17. **Range endpoints** (October 31, 2026: ranges are now compared through their published bounds for the North Dakota comparison, with no allowance, see "ND Insights color coding"; the annual-goal rule below is unchanged): does `0.29` mean "up to 29%" or "below 30%"? Are values rounded before binning? The website shows "20% to 29%". Until ND DPI documents this, any goal comparison that involves a published range shows "Goal status pending range clarification" with no verdict. No adjustment is assumed. Every Fort Yates achievement value published so far is a range, so all Fort Yates goal comparisons will be pending until this is resolved. When it is, `NdInsights.SchoolResults.compare_goal/2` is the single place to apply the documented rule.
18. **Open-ended range widths** (0–10%, 0–20%, 0–40%, 80–100%) vary by group with no documented rule, which makes many derived ranges wide (e.g. 0%–40%).
19. **Why grade 5 is never published for Fort Yates** (suppressed, or no tested students) is not stated.
20. **The test changed:** Insights says the achievement test was ND A+ in 2024-25 and NDSA in 2022-23 and 2023-24. Comparability across that change is unconfirmed, so year-over-year comparisons should be labeled before any trend charts are added.
21. **No annual goal year has matching imported data:** the PDF goals start in 2025-26 and the latest imported file is 2024-25, so every goal currently shows "No matching results in the imported data". Whether Insights has published 2025-26 results hasn't been independently verified; import the 2025-26 download once it is available.
22. ~~**Growth mapping unconfirmed:**~~ **Resolved October 31, 2026:** G2-M3 and G3-M3 are Overall Growth Percentiles (see "Growth-percentile decision"). Original note: whether the workbook's "met state growth expectations" (G2-M3, G3-M3) means Insights "Meets", or "Meets + Exceeds", for which grades and year, is unknown, so no comparison is made.
23. **Engagement mapping unconfirmed:** the workbook's G4 disengagement metrics plausibly correspond to the Engagement Survey "Disengaged" level by area, but the baseline year and survey grades are unstated, so no comparison is made. (November 1, 2026: the targets are shown beside Disengaged as "Not compared: population unverified"; G4-M1, observed active engagement, is not matched to survey Committed.)
    - **Engagement Participation, resolved:** the file's data dictionary describes its year columns as "percent of participants that fall into this engagement level", but the data contradicts that. The Committed, Compliant and Disengaged rows are identical for all 5,656 institution-years statewide (the state row reads 0.89 for each level), and Insights' Participation tab shows it as "Overall Participation — participation of the enrolled student body in the engagement survey", one series per year.
    - The live School values (87, 92, 92, 92, 97.5 for 2020-21 to 2024-25) are the midpoints of the CSV ranges, and the State values equal the CSV's exact state values.
    - The dashboard therefore shows it as **survey participation**, separate from the engagement categories. It is shown as a range, never a midpoint, and as a single value only when every published row agrees; otherwise each row is listed. All three source rows remain separate records.
24. **The data dictionaries are mostly empty** ("No Description Available"). The Comp/Reg/Alt and Partially meanings above come from the website, not the dictionary.
25. **The Insights website draws participation ranges at their midpoints** (e.g. 97.5 for 95–100%). Emisint does not; it shows the published range.
26. **Statewide duplicate InstitutionIDs:** some institutions appear under two names, or two schools share one ID, with different values (e.g. "Hope Page 85" / "Hope-Page 85"; "Badlands Elementary" / "Watford City Elementary"). These are treated as conflicts. None affect Fort Yates, but portfolio expansion will need a rule for them.
27. **Eligible assessment years per review checkpoint are not established:** which ND Insights school year should count for the 18- and 36-month reviews is undecided. Until it is, published years are reference only and any use is an explicit, recorded choice (see "Growth-percentile decision").
29. **Engagement benchmark years:** a middle-school benchmark is verified for 2021-22 and 2024-25 only. 2022-23 and 2023-24 Fort Yates figures mix survey versions (no published statewide figure for that mix). 2017-18 to 2020-21 have no verified brief. From 2025-26 the state moves to a state-developed survey (DPI bulletin), so the brief-based benchmark won't carry forward without new verification.
30. **Range rounding and endpoints are still undocumented.** Comparisons use the published bounds as published. A written DPI methodology would say whether a touching or near-endpoint result could go either way.
31. **Insights state Engagement "Compliant" equals "Committed"** in the Behavioral, Cognitive and Emotional downloads for every year. It looks like a publication defect; Compliant isn't rated, but it should be reported to DPI.
32. **Workbook assessment-year and assessment-type mapping for the main state tables:** which school year counts for the 18- and 36-month reviews (item 27), and whether the workbook's Proficient/Novice targets count the Combined, Standard or Alternate assessment, are not established. Until both are, `ResultGoals.established/0` stays empty and workbook targets beside published results are reference only. Record the decision there (and here) when made.

**Test issue (resolved October 31, 2026):**

28. ~~**Intermittent ND Insights import deadlock in tests.**~~ **Fixed; root cause found.**
    - **Evidence:** reproduced with `mix test … --repeat-until-failure 40` (seed 505259). The full log shows `ERROR 40P01 (deadlock_detected)`: "Process A waits for ShareLock on transaction X; blocked by process B", and the reverse. That is two transactions each waiting on the other's uncommitted insert of the same unique key.
    - **Cause (test isolation plus concurrent imports):**
      - Async tests run inside one SQL-sandbox transaction each, so every imported file's `source_files` row (unique SHA-256) and `state_results` rows (unique natural key plus version) stay locked until the test ends.
      - Two tests importing overlapping fixture files in different orders form a lock cycle.
      - The import error is reported inside `{:ok, reports}`, and setups matched only `{:ok, _}`. So the deadlock surfaced later as unrelated assertion failures: the admin-import "0 new · 144 already stored" count, and the student-group LiveView test.
      - The same race exists in production in a milder form: two concurrent uploads of one file collide on the SHA-256 index.
    - **Fixes:**
      1. `NdInsights.Importer` takes a transaction-scoped advisory lock (`pg_advisory_xact_lock`) before any write, and runs the revision check after the lock. Imports are serialized and never wait on each other's uncommitted rows.
      2. `test/support/nd_insights_fixtures.ex` adds `import_insights!/2`, which fails at the import with the file's error. It replaced every loose `{:ok, _}` setup.
      3. Regression tests in `importer_test.exs` check the lock is held for the import transaction, and that the revision check happens inside it.
    - **Verification:**
      - Before the fix: failures in 3 of 10 full runs and 1 of about 20 repeat runs.
      - After the fix: 41 consecutive full runs (257 tests each, `--repeat-until-failure 40`) with no failure and no 40P01, plus the original failing seed.
      - The three earlier failure kinds (importer deadlocks, admin count, student group) all trace to the same mechanism. Two were confirmed by their 40P01 logs; the other two were explained by the swallowed import error, which now fails loudly if it recurs.

## Risks and dependencies

- **`_dev` migration hazard (unresolved):** until `20260701032125_migrate_resources1_dev.exs` is converted by its owner, any `mix ash.codegen` run other than `--check` (including `--dry-run` and `--snapshots-only`) rolls it back and drops the three SSS tables. See unresolved item 13.
- Tasks 3–6 depend on 2. Tasks 7–11 depend on 3–6. Task 19 depends on 17. Task 16 depends on 13–15.
- These are the first tenant-scoped resources, so org-switching and forged-tenant tests are mandatory.
- **Orphaned tests:** `test/emisint/accounts/school_test.exs` was written for an older, Michigan-shaped `Accounts.School` (MDE codes, update action, `Registry.Enrollment`). It already fails (the module didn't exist) and will keep failing against the new resource. It is left untouched pending your decision. The same applies to the orphaned registry, compliance, analytics, and worker tests.
- Definitions are read-only. Changing a baseline, target, or weight later requires a versioned definition (`definition_version`) or an audited update (e.g. AshPaperTrail with `attributes_as_attributes [:organization_id]`), not an in-place edit.
- The repository lives in an iCloud-synced Desktop folder. Evicted files once made `git status` fail and recursive `grep` hang; the folder is currently set to "Keep Downloaded".
- Insights downloads aren't scriptable with curl (ASP.NET postback). They were obtained with a headless browser using the page's own controls. Future updates need the same, or a manual browser download into `references/nd_insights/`, followed by `mix nd_insights.import --institution-id 4300429212 references/nd_insights/*.csv`.
