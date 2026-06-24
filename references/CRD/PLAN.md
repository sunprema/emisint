# Plan — CRD (Composite Resident District) Import

## Approach

Add a new MDE-style import for the **Composite Resident District** dataset
(`references/CRD/CRD_List.csv`) following the established `emo_contact` import
pattern end-to-end: a shared **non-multitenant reference resource**, a streaming
CSV importer with bulk-upsert + error CSV, an Oban worker, an `MdeImportLog`
`:crd` type, domain registration, an `ash.codegen` migration, and a new
**Data Import** UI section (scope **b** — import pipeline + UI upload wiring).

### Data facts driving the design (verified against live DB)

- 27 rows. Columns: `School Year, Entity Name, District Code, Other Entity Name,
  CRD District Code, Grade, Number of Nonresident Students Enrolled`.
- **Composite key = `(school_year, charter_district_code, crd_district_code)`** —
  unique after the user removed the duplicate Ferndale row. Grade is ignored for the key.
- Charter `District Code` is reliable → **normalize leading zeros** (`String.trim_leading(code, "0")`,
  matching other importers) so it joins to `mde_districts`.
- **`CRD District Code` is NOT a real MDE code** (only 5/27 match by name) → store it
  **raw/opaque**; resolve the resident district to `mde_districts` **by normalized name**
  (best-effort, nullable `mde_district_id` when no match). See memory
  `crd-district-code-unreliable.md`.

### Proposed resource shape — `Emisint.Assessments.MdeCompositeResidentDistrict`

Table `mde_composite_resident_districts`, non-multitenant, system-admin write / all read.

| Field | Source column | Notes |
|---|---|---|
| `school_year` | School Year | part of key |
| `charter_district_code` | District Code | normalized; part of key |
| `charter_entity_name` | Entity Name | |
| `crd_district_code` | CRD District Code | raw/opaque; part of key |
| `resident_entity_name` | Other Entity Name | trustworthy resident identifier |
| `grade` | Grade | stored, not in key |
| `nonresident_students_enrolled` | Number of Nonresident Students Enrolled | integer |
| `mde_district_id` | (resolved by name) | nullable belongs_to `MdeDistrict` |

Identity `unique_crd` on `[:school_year, :charter_district_code, :crd_district_code]`.

## Tasks

- [x] **T1 — Resource**: `MdeCompositeResidentDistrict` (attrs above, `:create`/`:upsert`/`:update`/`:read`/`:destroy`, `unique_crd` identity, policies mirroring `MdeEmoContact`, nullable `mde_district` belongs_to).
- [x] **T2 — Domain registration**: register the resource + code-interface defines (`upsert_*`, `list_*`, `get_*_by_*`) in `lib/emisint/assessments.ex`.
- [x] **T3 — Migration**: `mix ash.codegen create_crd` + `mix ash.migrate`.
- [x] **T4 — Importer**: `MdeCompositeResidentDistrictImporter` — verified against real CSV: 27 records, 27 matched, 0 unmatched/errors, idempotent on re-run.
- [x] **T5 — `MdeImportLog` enum**: add `:crd` to `import_type` `one_of`.
- [x] **T6 — Worker**: `MdeCrdImportWorker` (queue `:data_ingestion`, PubSub topic `"crd_import"`), mirroring `MdeEmoContactImportWorker`.
- [x] **T7 — UI: DataImportLive**: `crd_*` assigns, PubSub subscribe (`"crd_import"`), 2 `handle_info` clauses, `upload_complete` clause, and a new "Composite Resident District" render section (neutral theme, matched/unmatched stats).
- [x] **T8 — UI: ImportHistoryLive**: `:crd` added to type filter, badge color, and `import_type_label`; plus the inline history badge in DataImportLive.
- [x] **T9 — Tests**: importer test (7 cases: stats, code normalization, raw CRD code, integer parse, name resolution + unmatched, idempotent upsert, BOM, missing file) + worker enqueue test. **7/7 passing.**

## Notes / Risks / Dependencies

- **Name-matching is best-effort.** Resident names like "Hamtramck, School District of the City of" vs `mde_districts` "Hamtramck…" need normalization; some rows will resolve `mde_district_id = nil`. The importer should count matched/unmatched and never fail a row on a missed name. The actual charter-vs-composite **comparison/scoring feature is OUT OF SCOPE** here (separate future pass).
- **T7 depends on T6**, T6 on T4, T4 on T1; T3 depends on T1+T2.
- `Storage.import_key/2` and the JS `TigrisUpload` hook are generic (`data-upload-type`), so no JS changes expected — confirm during T7.
- `String.to_existing_atom("#{type}_upload")` in DataImportLive requires the `crd_upload` / `crd_upload_progress` assigns to exist before any event fires (set in `mount`).
- Per project convention: verify CSV header strings match the importer's `@header_map` exactly (producer/consumer check) before considering T4 done.

---

**Awaiting your go-ahead.** Reply e.g. *"proceed with tasks T1, T2, T3"* and I'll start.
