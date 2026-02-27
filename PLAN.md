# Plan: Emisint Academic Performance Module (APM) — Full Implementation

## Context
Emisint is a greenfield SaaS platform for Michigan Charter School EMOs and Authorizers. The foundation is in place: Phoenix 1.8 + Ash Framework 3.x + AshPostgres + authentication (`Emisint.Accounts` domain with `User`/`Token`). The entire APM — 4 new domains, 14 resources, Oban workers, and LiveView dashboards — needs to be built on top of this foundation.

## Current State
- `Emisint.Accounts` domain: `User`, `Token` (auth works, migrations applied)
- Infrastructure ready: AshPaperTrail, AshOban, AshStateMachine, AshAdmin, Oban, DaisyUI all in `mix.exs` but unused
- No LiveViews, no `lib/emisint_web/live/` directory
- `config/config.exs` only registers `ash_domains: [Emisint.Accounts]`

---

## Approach
Build incrementally in 8 phases, each independently testable. Phases 0–5 are pure backend (Ash Resources + Oban workers). Phase 6 is the LiveView UI layer. Each phase ends with `mix ash.codegen <name> && mix ash.migrate` and passing tests before moving forward.

**Dependency order:** Organization → School → Student/AcademicYear/Enrollment → AssessmentResult → CharterContract/Schedule71Goal → GoalEvaluation → PerformanceSnapshot/Workers → LiveViews

---

## Tasks

### Phase 0: Foundation — Organization & User Roles
- [x] Create `lib/emisint/accounts/organization.ex` — primary tenant root (attrs: `name`, `type` atom `:emo|:authorizer`, `slug` unique, `active`)
- [x] Extend `lib/emisint/accounts/user.ex` — add `role` atom (`:emo_admin|:school_leader|:authorizer_liaison|:system_admin`), `organization_id` FK, `belongs_to :organization`
- [x] Add `Organization` to `lib/emisint/accounts.ex` resources + define code interface
- [x] Run `mix ash.codegen add_organization_and_user_roles && mix ash.migrate`
- [x] Write `test/emisint/accounts/organization_test.exs`

### Phase 1: Registry Domain
- [x] Create `lib/emisint/registry.ex` (new `Ash.Domain`)
- [x] Create `lib/emisint/registry/academic_year.ex` — attrs: `label`, `start_date`, `end_date`, 6 testing window date columns, `active`; multitenancy via `organization_id` attribute
- [x] Create `lib/emisint/registry/student.ex` — attrs: `uic` (Michigan UIC, unique per org), demographics, ESSA subgroup booleans (`:economically_disadvantaged`, `:english_learner`, `:special_education`); identity `[:uic, :organization_id]`; `:bulk_upsert` action for CSV import
- [x] Create `lib/emisint/registry/enrollment.ex` — attrs: `grade_level` atom, `status` atom, dates; relationships to `Student`, `AcademicYear`, `School` (forward ref resolved in Phase 2)
- [x] Append `Emisint.Registry` to `ash_domains` in `config/config.exs`
- [x] Run `mix ash.codegen add_registry_domain && mix ash.migrate`
- [x] Write tests for all three Registry resources

### Phase 2: School Resource (Accounts Domain)
- [x] Create `lib/emisint/accounts/school.ex` — attrs: `name`, `mde_district_code`, `mde_building_code` (critical for MDE data matching), `city`, `county`, `active`; multitenancy via `organization_id`; identity `[:mde_building_code, :organization_id]`
- [x] Extend `lib/emisint/accounts/user.ex` — add `school_id` FK + `belongs_to :school` (for School Leader scoping)
- [x] Add `School` to `lib/emisint/accounts.ex` resources + code interface
- [x] Run `mix ash.codegen add_school_resource && mix ash.migrate`
- [x] Write `test/emisint/accounts/school_test.exs`
    
### Phase 3: Assessments Domain
- [x] Create `lib/emisint/assessments.ex` (new `Ash.Domain`)
- [x] Create `lib/emisint/assessments/benchmark_provider.ex` — metadata for NWEA/i-Ready (attrs: `name`, `code` unique per org, `scoring_system` atom, `subjects` array)
- [x] Create `lib/emisint/assessments/assessment_result.ex` — attrs: `assessment_type` atom (`:m_step|:psat_8_9|:psat_10|:sat|:nwea_map|:i_ready`), `subject`, `testing_window`, `raw_score`, `scale_score`, `proficiency_level`, `sgp`, `growth_target`, `percentile`, `test_date`, `source`; identity `[:student_id, :academic_year_id, :assessment_type, :subject, :testing_window]`; `:bulk_upsert` action
- [x] Create `lib/emisint/assessments/competitor_data.ex` — pre-aggregated MDE public district data (attrs: `district_name`, `mde_district_code`, `subject`, `grade_level`, `proficiency_rate`, `average_sgp`, `student_count`, `academic_year_label`)
- [x] Append `Emisint.Assessments` to `ash_domains`
- [x] Run `mix ash.codegen add_assessments_domain && mix ash.migrate`
- [x] Write `test/emisint/assessments/assessment_result_test.exs` (test upsert identity)

### Phase 4: Compliance Domain
- [x] Create `lib/emisint/compliance.ex` (new `Ash.Domain`)
- [x] Create `lib/emisint/compliance/charter_contract.ex` — attrs: `authorizer_name`, `contract_start_date`, `contract_end_date`, `reauthorization_date`, `status` atom; `belongs_to :school`; AshPaperTrail extension
- [x] Create `lib/emisint/compliance/schedule71_goal.ex` — attrs: `title`, `goal_type` atom (`:proficiency_threshold|:sgp_median|:outperform_district|:growth_target`), `subject`, `grade_levels` array, `testing_window`, `target_value` decimal, `comparison_operator` atom, `exceeds_threshold`, `approaching_threshold`, `subgroup` atom; AshPaperTrail extension
- [x] Create `lib/emisint/compliance/goal_evaluation.ex` — stored snapshot resource; attrs: `status` atom (`:exceeds|:meets|:approaching|:below|:insufficient_data`), `actual_value`, `target_value`, `data_points_count`, `evaluated_at`; AshPaperTrail extension
- [x] Create `lib/emisint/compliance/changes/compute_goal_actual_value.ex` — custom `Ash.Resource.Change` that queries `AssessmentResult` aggregates per goal type (SGP median, proficiency rate, district comparison)
- [x] Create `lib/emisint/compliance/calculations/evaluate_goal_status.ex` — `Ash.Calculation` mapping actual vs threshold values → status atom
- [x] Append `Emisint.Compliance` to `ash_domains`
- [x] Run `mix ash.codegen add_compliance_domain && mix ash.migrate`
- [x] Write `test/emisint/compliance/goal_evaluation_test.exs` (test each goal_type branch in ComputeGoalActualValue)
- [x] Verify PaperTrail version records created on Schedule71Goal update

### Phase 5: Analytics Domain + Oban Workers
- [x] Create `lib/emisint/analytics.ex` (new `Ash.Domain`)
- [x] Create `lib/emisint/analytics/data_sync_log.ex` — attrs: `job_type` atom, `status` atom (`:pending|:running|:completed|:failed`), `records_processed`, `records_failed`, `error_message`, `started_at`, `completed_at`, `metadata` map
- [x] Create `lib/emisint/analytics/performance_snapshot.ex` — pre-aggregated cache; attrs: `snapshot_type` atom, `subject`, `grade_level`, `subgroup`, `testing_window`, `proficiency_rate`, `average_sgp`, `median_sgp`, `student_count`; identity on `[:school_id, :academic_year_id, :snapshot_type, :subject, :grade_level, :subgroup, :testing_window]`; `:upsert` action
- [x] Create `lib/emisint/analytics/intervention_trigger.ex` — attrs: `trigger_type` atom, `severity` atom, `triggered_at`, `status` atom; AshStateMachine for `active → resolved/dismissed` transitions
- [x] Create `lib/emisint/workers/csv_import_worker.ex` — Oban worker (queue: `:data_ingestion`): parse CSV, map columns by `provider_code`, bulk upsert AssessmentResults, update DataSyncLog, enqueue SnapshotRefreshWorker
- [x] Create `lib/emisint/workers/snapshot_refresh_worker.ex` — Oban worker (queue: `:analytics`): aggregate AssessmentResults by school/grade/subject/subgroup, upsert PerformanceSnapshots, enqueue GoalRecalculationWorker
- [x] Create `lib/emisint/workers/goal_recalculation_worker.ex` — Oban worker (queue: `:analytics`): call GoalEvaluation `:recalculate` action for each active Schedule71Goal, update InterventionTriggers
- [x] Add `data_ingestion: 5, analytics: 5` queues to Oban config in `config/config.exs`
- [x] Append `Emisint.Analytics` to `ash_domains`
- [x] Run `mix ash.codegen add_analytics_domain && mix ash.migrate`
- [x] Write `test/emisint/workers/csv_import_worker_test.exs` with fixture NWEA CSV
- [x] Write `test/emisint/workers/snapshot_refresh_worker_test.exs`

### Phase 6: LiveView Dashboard Layer
- [x] Create `lib/emisint_web/live/dashboard/portfolio_live.ex` — EMO portfolio overview: all schools with traffic-light goal status grid, DaisyUI stats cards
- [x] Create `lib/emisint_web/live/school/show_live.ex` — school drill-down with tabs: Proficiency / Growth / Compliance / Interventions (uses PerformanceSnapshot for speed)
- [x] Create `lib/emisint_web/live/compliance/tracker_live.ex` — Schedule 7-1 tracker: all goals for a school with colored status badges (DaisyUI badge-success/warning/error)
- [x] Create `lib/emisint_web/live/growth/monitor_live.ex` — SGP and NWEA monitor: median SGP by grade/subject, growth-to-target percentage
- [x] Create `lib/emisint_web/live/admin/data_import_live.ex` — CSV upload UI using `Phoenix.LiveView.upload`, real-time DataSyncLog status via PubSub
- [x] Update `lib/emisint_web/router.ex` — add authenticated LiveView routes under `ash_authentication_live_session`
- [x] Update `lib/emisint_web/components/layouts.ex` — replace boilerplate navbar with Emisint app shell (sidebar nav with DaisyUI drawer for mobile)
- [ ] Manually test all routes and role-based access restrictions

### Phase 7: Seeds + AshAdmin + Integration Tests
- [x] Add all domains to AshAdmin in `router.ex` (`ash_admin "/"` — auto-discovers all registered domains)
- [x] Populate `priv/repo/seeds.exs` with sample org, 2 schools, academic year, 3 users, 18 students, M-STEP + NWEA MAP results, charter contracts, Schedule71Goals; runs workers inline to populate snapshots + evaluations
- [x] Write `test/emisint/integration/data_pipeline_test.exs` — end-to-end: student → enrollment → assessment result → snapshot → goal evaluation (11 tests)
- [x] Write `test/emisint/integration/csv_import_test.exs` — CSV upload → worker → snapshot → goal recalculation chain (14 tests)

### Phase 8: Reporting & Exports (deferred)
- [ ] Create `lib/emisint/reporting/reauthorization_packet.ex` — multi-year data aggregation for charter renewal
- [ ] Create `lib/emisint/reporting/board_report.ex` — monthly board report data
- [ ] Create `lib/emisint_web/live/reports/report_builder_live.ex` — report parameter UI
- [ ] Create `lib/emisint/workers/report_generation_worker.ex` — async PDF generation via Oban

---

## Critical Files to Create/Modify

| File | Action |
|------|--------|
| `lib/emisint/accounts/organization.ex` | Create (Phase 0) |
| `lib/emisint/accounts/school.ex` | Create (Phase 2) |
| `lib/emisint/accounts/user.ex` | Modify — add `role`, `organization_id`, `school_id` |
| `lib/emisint/accounts.ex` | Modify — add School, Organization to resources |
| `config/config.exs` | Modify — expand `ash_domains` list each phase |
| `lib/emisint/compliance/changes/compute_goal_actual_value.ex` | Create (Phase 4) — the APM core engine |
| `lib/emisint/workers/csv_import_worker.ex` | Create (Phase 5) |
| `lib/emisint_web/router.ex` | Modify (Phase 6) — add LiveView routes + AshAdmin domains |
| `lib/emisint_web/components/layouts.ex` | Modify (Phase 6) — app shell |

---

## Notes & Risks

- **Forward reference (Risk):** `Enrollment.belongs_to :school` references `Emisint.Accounts.School` which is built in Phase 2. Define the relationship in Phase 1 but defer generating the `school_id` FK column to Phase 2's codegen run.
- **Cross-domain queries (Risk):** `ComputeGoalActualValue` (Compliance) queries `AssessmentResult` (Assessments). Use `Ash.read!/2` with explicit `domain: Emisint.Assessments` option and pass the actor from changeset context through.
- **Oban worker auth (Risk):** Workers run without an HTTP actor. Use `authorize?: false` for system-initiated writes in workers, or add a `:system_admin` role and create a per-org system user.
- **`ash_domains` config:** Must be updated in `config/config.exs` **before** each `mix ash.codegen` run or the tool won't discover new resources.
- **PaperTrail migration order:** `ash.codegen` auto-generates version tables. Review generated migrations to ensure base tables precede version tables.
- **Multi-tenancy pattern:** All resources (except `Organization` itself) use `multitenancy do strategy :attribute; attribute :organization_id end`. LiveView mounts must extract `actor.organization_id` and pass as `tenant:` option to all Ash action calls.
- **Phase 4 is the highest complexity:** `GoalEvaluation` with branching calculation logic is the core APM differentiator. Budget extra time for testing all `goal_type` branches.

---

## Verification Plan
1. After each phase: `mix compile` (zero warnings) + `mix test` (all green)
2. After Phase 2: `mix phx.server` + navigate to `localhost:4000/admin` — all domains visible in AshAdmin
3. After Phase 5: `localhost:4000/oban` shows 3 queues (default, data_ingestion, analytics)
4. After Phase 6: Full manual walkthrough as each of the 3 user roles (EMO Admin, School Leader, Authorizer Liaison)
5. After Phase 7: `mix run priv/repo/seeds.exs` populates dev DB; integration tests cover the full data pipeline
