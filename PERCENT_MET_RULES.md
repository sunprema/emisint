# PercentMet Processing Rules

This document describes the rules applied when importing and displaying the
`PercentMet` field from MDE state assessment CSV files into Emisint.

---

## Rule 1: Data Suppression (`"*"`)

**Source value:** `*`

MDE publishes `"*"` when the cohort for a given row has fewer than 10 students.
Under Federal FERPA regulations, the exact percentage cannot be disclosed, so it
is replaced with `"*"`.

### Import behaviour
- `percent_met` is stored as `nil`
- `percent_met_suppressed` is set to `true`

### Calculation behaviour
- Rows where `percent_met_suppressed = true` are **excluded** from all weighted
  average calculations (e.g. grade-level proficiency aggregates in
  `weighted_proficiency_float/1`)
- Including them as `0.0` would artificially deflate averages — exclusion is the
  correct treatment

### Display behaviour
- When `percent_met_suppressed = true` and `percent_met` is `nil`, the UI shows
  `*` instead of `—`
- `—` is reserved for rows where data is genuinely absent (no records found)

### Implementation
| Layer | Location |
|---|---|
| Import flag | `Emisint.Assessments.MdeImporter.suppressed?/1` |
| DB field | `mde_state_assessment_results.percent_met_suppressed` (boolean, default `false`) |
| Calculation exclusion | `weighted_proficiency_float/1` in worker + LiveView |
| Snapshot flag | `"school_ela_suppressed"`, `"school_math_suppressed"` in `MdeSchoolVsLeaSnapshot.grade_breakdown` JSON |
| Display | `pct_badge` component — renders `*` when `suppressed={true}` |

---

## Rule 2: Range / Approximate Values

**Source values:** `<=5%`, `<=10%`, `<=20%`, `<=50%`, `>=50%`, `>=80%`, `>90%`, `>=95%`

MDE publishes range-bounded strings when the exact value would indirectly
identify a small cohort that is not fully suppressed. The numeric boundary is
used as the stored value.

### Mapping table

| CSV value | Stored `percent_met` |
|---|---|
| `<=5%` | `5` |
| `<=10%` | `10` |
| `<=20%` | `20` |
| `<=50%` | `50` |
| `>=50%` | `50` |
| `>=80%` | `80` |
| `>90%` | `90` |
| `>=95%` | `95` |

Any `<`, `<=`, `>`, `>=` prefixed value with an optional `%` suffix is handled
by the same regex — including decimal variants not listed above.

### Import behaviour
- The numeric boundary is extracted via `strip_range_operators/1` and stored as
  a `Decimal` in `percent_met`
- `percent_met_approximate` is set to `true`
- `percent_met_suppressed` remains `false` (the value is usable in calculations)

### Calculation behaviour
- Approximate rows **are included** in weighted average calculations — the
  boundary value is a valid estimate
- The `percent_met_approximate` flag does not affect calculation logic

### Display behaviour
- The value is displayed normally (e.g. `50%`)
- A **light yellow background** (`bg-yellow-200`) is applied to the badge to
  signal to the user that the value is a boundary approximation, not an exact
  percentage

### Implementation
| Layer | Location |
|---|---|
| Import flag | `Emisint.Assessments.MdeImporter.approximate?/1` |
| Value extraction | `Emisint.Assessments.MdeImporter.strip_range_operators/1` |
| Regex | `@range_pattern ~r/^[<>]=?\s*(\d+(?:\.\d+)?)\s*%?$/` |
| DB field | `mde_state_assessment_results.percent_met_approximate` (boolean, default `false`) |
| Snapshot flag | `"school_ela_approximate"`, `"school_math_approximate"` in `MdeSchoolVsLeaSnapshot.grade_breakdown` JSON |
| Display | `pct_badge` component — adds `bg-yellow-200 px-1 rounded` when `approximate={true}` |

---

## Summary

| CSV value | `percent_met` | `percent_met_suppressed` | `percent_met_approximate` | Display |
|---|---|---|---|---|
| `71.4%` | `71.4` | `false` | `false` | `71.4%` (normal) |
| `<=50%` | `50` | `false` | `true` | `50%` (yellow bg) |
| `>=95%` | `95` | `false` | `true` | `95%` (yellow bg) |
| `*` | `nil` | `true` | `false` | `*` |
| `""` / missing | `nil` | `false` | `false` | `—` |

---

## Re-processing Existing Data

Since these rules were added after initial import, existing rows in
`mde_state_assessment_results` have default values (`percent_met_suppressed =
false`, `percent_met_approximate = false`). To apply the rules to existing data:

1. **Re-import the CSV:**
   ```elixir
   Emisint.Assessments.MdeImporter.import_file("path/to/mstep_file.csv")
   ```

2. **Regenerate snapshots** for the affected school year:
   ```elixir
   Emisint.Workers.MdeComparisonSnapshotWorker.perform(
     %Oban.Job{args: %{"school_year" => "24 - 25 School Year"}}
   )
   ```
