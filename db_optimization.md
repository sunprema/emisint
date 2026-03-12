# DB Optimization Session

## Core Patterns Applied

### 1. `connected?` Guard in LiveView `mount/3`
Phoenix LiveView mounts **twice** per page visit — once on the HTTP pass (server-side render) and once on the WebSocket pass. Without a guard, every DB query fires twice.

**Fix:** Defer all DB work to the connected pass only, assign nil/empty defaults for the disconnected pass.

```elixir
def mount(_params, _session, socket) do
  socket = socket |> assign(:data, []) |> assign(:page_title, "...")

  if connected?(socket) do
    data = load_data()
    {:ok, assign(socket, :data, data)}
  else
    {:ok, socket}
  end
end
```

### 2. Parallel Queries with `Task.async` / `Task.await`
Independent DB queries were running sequentially. Running them in parallel cuts wall-clock time to the slowest single query.

```elixir
task_a = Task.async(fn -> query_a() end)
task_b = Task.async(fn -> query_b() end)
a = Task.await(task_a)
b = Task.await(task_b)
```

For queries with dependencies, use two sequential batches where each batch is internally parallel.

### 3. `Ash.Query.select/2` — Column Pruning
Wide tables (especially `MdeEntityMaster` with 50+ columns, `MdeDistrictSnapshot` with JSONB columns) were loading all columns even when only a handful were needed for list views.

```elixir
Ash.Query.select([:col_a, :col_b, :col_c])
```

### 4. Lazy-Load Detail Data on Click
Detail panels / modals that show the full record are only opened by user interaction. Load only list-needed columns upfront; fetch the full record on demand.

### 5. Eliminate Duplicate Queries
Same table queried twice with overlapping filters — deduplicate by reusing the already-fetched result.

### 6. Pagination Instead of Full Table Loads
Large tables loaded in full on every page mount replaced with offset-based pagination (`limit: 100`). COUNT(*) only fires when the result set changes (year/search change), not on prev/next navigation.

### 7. pg_trgm GIN Index for `ilike` Search
`ilike '%term%'` on large string columns causes full table scans. A GIN trigram index makes these fast.

---

## Files Changed

### `lib/emisint_web/live/mde/overview_live.ex`
**Problems:**
- No `connected?` guard — full table scan on every HTTP pass
- Loading ELA%, Math%, Avg Proficient columns (JSONB) for a list view that didn't display them
- Loading all rows (~5k+) at once; no pagination
- `load_school_years` querying large `MdeStateAssessmentResult` table instead of the smaller `MdeDistrictSnapshot`
- COUNT(*) fired on every pagination navigation

**Fixes:**
- Added `connected?` guard
- Removed unused columns (ELA%, Math%, Avg Proficient) from list query
- Added offset pagination (100 records/page) with `Ash.Query.select` for list columns only
- Switched `load_school_years` to query `MdeDistrictSnapshot` (smaller, indexed)
- Split `load_page/3` (with COUNT) and `load_page_rows/3` (without COUNT) — count only on year/search change
- Modal still loads full snapshot lazily on row click
- Removed stat cards that required additional aggregation queries

---

### `lib/emisint/assessments/mde_district_snapshot.ex`
**Problem:** No paginated read action existed.

**Fix:** Added `:list_by_year` read action with `pagination offset?: true, countable: true`.

---

### `lib/emisint/repo.ex` + migration
**Problem:** `ilike '%term%'` on `district_name` caused full table scans.

**Fix:**
- Added `"pg_trgm"` to `installed_extensions/0`
- Created GIN trigram index manually in migration SQL (AshPostgres DSL does not support `opclasses`):

```sql
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE INDEX IF NOT EXISTS mde_district_snapshots_district_name_gin_trgm_idx
ON mde_district_snapshots
USING gin (district_name gin_trgm_ops);
```

---

### `lib/emisint_web/live/mde/district_analysis_live.ex`
**Problems:**
- No `connected?` guard
- 6+ sequential queries in `handle_params` and `handle_event`
- `load_school_years` querying `MdeStateAssessmentResult` unnecessarily
- `load_all_districts` loading all columns from `MdeDistrictSnapshot`
- `load_econ_grade_breakdown` running 3 inner queries sequentially

**Fixes:**
- Added `is_connected` assign pattern (stored in socket so `handle_params` can check it)
- `handle_params` / `handle_event("select_year")`: skips all DB on disconnected pass
- **Batch 1** (parallel): `load_school_vs_lea`, `load_enrollment`, `load_sat_results`, `load_sat_state_result`
- **Batch 2** (parallel): `load_sat_lea_result` + `load_econ_grade_breakdown` (both depend on `lea_dc` from batch 1)
- Switched `load_school_years` to `MdeDistrictSnapshot`
- Added `Ash.Query.select([:district_code, :district_name, :entity_type])` to `load_all_districts`
- Parallelized 3 inner queries inside `load_econ_grade_breakdown`

---

### `lib/emisint_web/live/dashboard/portfolio_live.ex`
**Problems:**
- No `connected?` guard — 3 queries fired on every HTTP pass
- Default `goal_counts: %{}` caused key-not-found crash on disconnected pass

**Fixes:**
- Added `connected?` guard with empty defaults
- Parallelized all 3 queries: `School`, `GoalEvaluation` (with goal load), `InterventionTrigger`
- Fixed default: `%{on_track: 0, approaching: 0, below: 0, insufficient: 0}`

---

### `lib/emisint_web/live/school/health_score_live.ex`
**Problems:**
- No `connected?` guard — 4 queries fired on every HTTP pass

**Fixes:**
- Added `connected?` guard with `scored_schools: []` default
- Parallelized all 4 queries: `School`, `PerformanceSnapshot`, `GoalEvaluation`, `InterventionTrigger`
- `HealthScore.compute` grouping/scoring only runs after all tasks resolve

---

### `lib/emisint_web/live/school/show_live.ex`
**Problems:**
- No `connected?` guard
- `get_school!` and `list_academic_years!` ran sequentially before dependent queries
- Template accessed `@school.name` etc. directly — crashed on disconnected pass (nil)

**Fixes:**
- Added `connected?` guard with nil defaults
- **Batch 1** (parallel): `get_school!` + `list_academic_years!`
- **Batch 2** (parallel): `load_snapshots`, `load_goals_with_evals`, `load_triggers` (all depend on school_id resolved in batch 1)
- Added `:if={@school}` guard on main template div

---

### `lib/emisint_web/live/compliance/tracker_live.ex`
**Problems:**
- No `connected?` guard — 2 queries fired on every HTTP pass
- `get_school!` and `load_goals_with_evals` ran sequentially (independent queries)
- Template accessed `@school.id` / `@school.name` directly — crashed on disconnected pass

**Fixes:**
- Added `connected?` guard with nil/empty defaults
- Parallelized `get_school!` + `load_goals_with_evals`
- Added `:if={@school}` guard on main template div

---

### `lib/emisint_web/live/admin/organization_show_live.ex`
**Problem:** `load_data/2` (called from mount + event handlers) ran `get_organization!` and `list_users!` sequentially.

**Fix:** Parallelized both queries with `Task.async` inside `load_data/2` — applies to all call sites automatically.

---

### `lib/emisint_web/live/mde/entity_master_live.ex`
**Problems:**
- No `connected?` guard — full `MdeEntityMaster` read (~5k rows × 50+ columns) on every HTTP pass
- `load_all_entities` loaded all 50+ columns for a list view needing only ~11
- Detail modal loaded from in-memory list (already had all columns); no lazy-load

**Fixes:**
- Added `connected?` guard with empty defaults
- Added `Ash.Query.select` with only the 11 list/filter/stats columns:
  `entity_code`, `entity_official_name`, `district_official_name`, `isd_official_name`,
  `entity_type_group_name`, `entity_type_name`, `entity_county_name`,
  `entity_actual_grades`, `entity_authorized_grades`, `entity_status`, `entity_type_category_name`
- Detail modal now lazy-loads the full entity record on click via `entity_code` lookup
- Changed `phx-value-index` → `phx-value-code` on table rows

---

### `lib/emisint/reports/school/school_vs_lea_pdf.ex`
**Problems:**
- 6 sequential DB queries (snapshot → enrollment → sat_data → entity_details → school_row → lea_row → state_row)
- Duplicate `MdeSatResult` query: `load_sat_data` fetched building-level rows, then `load_sat_score_bars` re-queried the same table for just the "All Students" row
- `MdeEntityMaster` loaded all 50+ columns; only 6 used

**Fixes:**
- **Batch 1** (parallel): snapshot + enrollment + sat_raw + entity_details — all 4 fire simultaneously
- Eliminated duplicate school_row query — extracted from already-loaded `sat_raw` structs: `Enum.find(sat_raw, &(...subgroup == "All Students"))`
- Split `load_sat_data` into `load_sat_raw/2` (returns raw structs for reuse) + `sat_raw_to_display/1` (maps to PDF shape)
- **Batch 2** (parallel): lea_row + state_row in `load_sat_score_bars`
- Added `Ash.Query.select(@entity_select)` to `load_entity_details` — 6 columns only

**Net result:** 6 sequential queries → 2 parallel batches (4+2) with one query eliminated entirely.

---

## Summary Table

| File | Connected? Guard | Parallel Queries | Column Pruning | Lazy Load | Duplicate Removed |
|---|---|---|---|---|---|
| `overview_live.ex` | ✅ | — | ✅ | ✅ modal | — |
| `district_analysis_live.ex` | ✅ | ✅ 2 batches | ✅ districts | — | — |
| `portfolio_live.ex` | ✅ | ✅ 3 parallel | — | — | — |
| `health_score_live.ex` | ✅ | ✅ 4 parallel | — | — | — |
| `show_live.ex` | ✅ | ✅ 2 batches | — | — | — |
| `tracker_live.ex` | ✅ | ✅ 2 parallel | — | — | — |
| `organization_show_live.ex` | — | ✅ 2 parallel | — | — | — |
| `entity_master_live.ex` | ✅ | — | ✅ 11/50+ cols | ✅ modal | — |
| `school_vs_lea_pdf.ex` | — | ✅ 2 batches | ✅ 6/50+ cols | — | ✅ school_row |
