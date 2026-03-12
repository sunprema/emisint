defmodule Emisint.Reports.School.SchoolVsLeaPdf do
  @template_path "priv/typst/school/school_vs_lea.typ"

  require Ash.Query

  alias Emisint.Assessments.{
    MdeEnrollmentResult,
    MdeEntityMaster,
    MdeSatResult,
    MdeSchoolVsLeaSnapshot
  }

  @doc """
  Generates a School vs Geographic LEA PDF for the given building code and school year.

  Returns `{:ok, pdf_binary}` or `{:error, reason}`.
  """
  def generate_report(building_code, year, _opts \\ []) do
    template = File.read!(Application.app_dir(:emisint, @template_path))
    data = build_data(building_code, year)
    config = Imprintor.Config.new(template, data)
    Imprintor.compile_to_pdf(config)
  end

  # --- Data fetching ---

  defp build_data(building_code, year) do
    # Batch 1: four independent queries — run in parallel.
    snapshot_task =
      Task.async(fn ->
        MdeSchoolVsLeaSnapshot
        |> Ash.Query.for_read(:by_building_and_year, %{
          building_code: building_code,
          school_year: year
        })
        |> Ash.read_one!(authorize?: false)
      end)

    enrollment_task = Task.async(fn -> load_enrollment_data(building_code, year) end)
    sat_raw_task = Task.async(fn -> load_sat_raw(building_code, year) end)
    entity_task = Task.async(fn -> load_entity_details(building_code) end)

    snapshot = Task.await(snapshot_task)
    enrollment = Task.await(enrollment_task)
    sat_raw = Task.await(sat_raw_task)
    entity_details = Task.await(entity_task)

    sat_results = sat_raw_to_display(sat_raw)
    # Reuse the already-loaded raw rows — no second DB hit needed.
    school_sat_row = Enum.find(sat_raw, &((&1.subgroup || "All Students") == "All Students"))

    case snapshot do
      nil ->
        # No snapshot computed yet — return minimal safe structure
        %{
          school: %{
            name: building_code,
            building_code: building_code,
            report_date: Date.utc_today() |> Calendar.strftime("%b %d, %Y")
          },
          school_year: year,
          lea: %{district_code: "", district_name: ""},
          above_lea: 0,
          below_lea: 0,
          above_state: 0,
          grades_compared: 0,
          subjects: [],
          all_subjects_avg: %{school_pct: nil, lea_pct: nil, state_pct: nil, delta: nil},
          grade_breakdown: [],
          enrollment: enrollment,
          sat_results: sat_results,
          sat_score_bars: [],
          entity_details: entity_details
        }

      snap ->
        subjects = snapshot_to_subjects(snap.subject_comparison)
        grades = snapshot_to_grades(snap.grade_breakdown)
        all_subjects_avg = snapshot_to_all_subjects_avg(snap.all_subjects_avg)
        sat_score_bars = load_sat_score_bars(school_sat_row, snap.lea_district_code, year)

        %{
          school: %{
            name: snap.school_name || building_code,
            building_code: building_code,
            report_date: Date.utc_today() |> Calendar.strftime("%b %d, %Y")
          },
          school_year: year,
          lea: %{
            district_code: snap.lea_district_code || "",
            district_name: snap.lea_district_name || ""
          },
          above_lea: snap.above_lea,
          below_lea: snap.below_lea,
          above_state: snap.above_state,
          grades_compared: snap.grades_compared,
          subjects: subjects,
          all_subjects_avg: all_subjects_avg,
          grade_breakdown: grades,
          enrollment: enrollment,
          sat_results: sat_results,
          sat_score_bars: sat_score_bars,
          entity_details: entity_details
        }
    end
  end

  defp load_enrollment_data(building_code, year) do
    record =
      MdeEnrollmentResult
      |> Ash.Query.filter(
        building_code == ^building_code and
          school_year == ^year and
          rollup_level == :building
      )
      |> Ash.read_one!(authorize?: false)

    case record do
      nil ->
        %{total: nil, male: nil, female: nil, male_pct: nil, female_pct: nil}

      rec ->
        %{
          total: rec.total_enrollment,
          male: rec.male_enrollment,
          female: rec.female_enrollment,
          male_pct: safe_pct(rec.male_enrollment, rec.total_enrollment),
          female_pct: safe_pct(rec.female_enrollment, rec.total_enrollment)
        }
    end
  end

  @entity_select [
    :isd_code,
    :isd_official_name,
    :entity_chartering_agency_code,
    :entity_chartering_agency_name,
    :entity_authorized_grades,
    :entity_actual_grades
  ]

  defp load_entity_details(building_code) do
    record =
      MdeEntityMaster
      |> Ash.Query.filter(entity_code == ^building_code)
      |> Ash.Query.select(@entity_select)
      |> Ash.read_one!(authorize?: false)

    case record do
      nil ->
        %{
          isd_code: nil,
          isd_official_name: nil,
          entity_chartering_agency_code: nil,
          entity_chartering_agency_name: nil,
          entity_authorized_grades: nil,
          entity_actual_grades: nil
        }

      rec ->
        %{
          isd_code: rec.isd_code,
          isd_official_name: rec.isd_official_name,
          entity_chartering_agency_code: rec.entity_chartering_agency_code,
          entity_chartering_agency_name: rec.entity_chartering_agency_name,
          entity_authorized_grades: rec.entity_authorized_grades,
          entity_actual_grades: rec.entity_actual_grades
        }
    end
  end

  @sat_subgroups ["All Students", "Economically Disadvantaged"]

  # Returns raw structs so build_data can extract the school row for reuse.
  defp load_sat_raw(building_code, year) do
    MdeSatResult
    |> Ash.Query.filter(
      building_code == ^building_code and school_year == ^year and rollup_level == :building
    )
    |> Ash.Query.sort(:subgroup)
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&((&1.subgroup || "All Students") in @sat_subgroups))
  end

  defp sat_raw_to_display(sat_raw) do
    Enum.map(sat_raw, fn row ->
      %{
        subgroup: row.subgroup || "All Students",
        num_assessed: row.math_num_assessed,
        math_score_average: decimal_to_float(row.math_score_average),
        ebrw_score_average: decimal_to_float(row.ebrw_score_average),
        all_subject_score_average: decimal_to_float(row.all_subject_score_average)
      }
    end)
  end

  # school_row is passed in (already fetched by load_sat_raw) — no duplicate query.
  # lea_row and state_row run in parallel.
  defp load_sat_score_bars(school_row, lea_district_code, year) do
    lea_task =
      Task.async(fn ->
        if lea_district_code do
          MdeSatResult
          |> Ash.Query.filter(
            district_code == ^lea_district_code and school_year == ^year and
              rollup_level == :district and subgroup == "All Students"
          )
          |> Ash.read_one!(authorize?: false)
        end
      end)

    state_task =
      Task.async(fn ->
        MdeSatResult
        |> Ash.Query.filter(
          rollup_level == :isd and isd_code == "0" and school_year == ^year and
            subgroup == "All Students"
        )
        |> Ash.read_one!(authorize?: false)
      end)

    lea_row = Task.await(lea_task)
    state_row = Task.await(state_task)

    school_math = school_row && decimal_to_float(school_row.math_score_average)
    school_ebrw = school_row && decimal_to_float(school_row.ebrw_score_average)
    school_all = school_row && decimal_to_float(school_row.all_subject_score_average)

    if is_nil(school_math) and is_nil(school_ebrw) and is_nil(school_all) do
      []
    else
      [
        %{
          subject: "Math Score",
          school: school_math,
          lea: lea_row && decimal_to_float(lea_row.math_score_average),
          state: state_row && decimal_to_float(state_row.math_score_average),
          max_val: 800
        },
        %{
          subject: "EBRW Score",
          school: school_ebrw,
          lea: lea_row && decimal_to_float(lea_row.ebrw_score_average),
          state: state_row && decimal_to_float(state_row.ebrw_score_average),
          max_val: 800
        },
        %{
          subject: "All Score",
          school: school_all,
          lea: lea_row && decimal_to_float(lea_row.all_subject_score_average),
          state: state_row && decimal_to_float(state_row.all_subject_score_average),
          max_val: 1600
        }
      ]
    end
  end

  defp decimal_to_float(nil), do: nil
  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)

  # Coerces any numeric-ish value from JSONB to a plain Elixir float.
  # JSONB round-trips through Jason; numbers come back as float/integer.
  # String values (double-encoded snapshots) are parsed defensively.
  defp to_float(nil), do: nil
  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)

  defp to_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp safe_pct(num, den) when is_integer(num) and is_integer(den) and den > 0,
    do: Float.round(num / den * 100, 1)

  defp safe_pct(_, _), do: nil

  # --- Snapshot → PDF data shape converters ---

  defp snapshot_to_subjects(nil), do: []

  defp snapshot_to_subjects(list) do
    Enum.map(list, fn row ->
      row = if is_binary(row), do: Jason.decode!(row), else: row

      %{
        subject: row["subject"],
        school_pct: to_float(row["school_pct"]),
        lea_pct: to_float(row["lea_pct"]),
        state_pct: to_float(row["state_pct"]),
        delta: to_float(row["delta"]),
        school_vs_state_delta: to_float(row["school_vs_state_delta"])
      }
    end)
  end

  defp snapshot_to_grades(nil), do: []

  defp snapshot_to_grades(list) do
    Enum.map(list, fn row ->
      row = if is_binary(row), do: Jason.decode!(row), else: row
      grade = row["grade"]

      school_ela = to_float(row["school_ela"])
      school_math = to_float(row["school_math"])
      school_ela_suppressed = row["school_ela_suppressed"] || false
      school_ela_approximate = row["school_ela_approximate"] || false
      school_math_suppressed = row["school_math_suppressed"] || false
      school_math_approximate = row["school_math_approximate"] || false

      %{
        grade: "Grade #{grade}",
        school_ela: school_ela,
        school_ela_suppressed: school_ela_suppressed,
        school_ela_approximate: school_ela_approximate,
        school_ela_display: grade_display(school_ela, school_ela_suppressed, school_ela_approximate),
        lea_ela: to_float(row["lea_ela"]),
        state_ela: to_float(row["state_ela"]),
        ela_delta: to_float(row["ela_delta"]),
        school_math: school_math,
        school_math_suppressed: school_math_suppressed,
        school_math_approximate: school_math_approximate,
        school_math_display: grade_display(school_math, school_math_suppressed, school_math_approximate),
        lea_math: to_float(row["lea_math"]),
        state_math: to_float(row["state_math"]),
        math_delta: to_float(row["math_delta"])
      }
    end)
  end

  # Produces a display string for the PDF template:
  #   - "*"       when suppressed (FERPA Rule 1)
  #   - "X.X%*"   when a Rule 2 range approximation (yellow bg in UI)
  #   - "X.X%"    when an exact value
  #   - "—"       when no data
  defp grade_display(nil, true, _approximate), do: "*"
  defp grade_display(nil, _suppressed, _approximate), do: "—"
  defp grade_display(value, _suppressed, true), do: "#{Float.round(value * 1.0, 1)}%*"
  defp grade_display(value, _suppressed, _approximate), do: "#{Float.round(value * 1.0, 1)}%"

  defp snapshot_to_all_subjects_avg(nil),
    do: %{school_pct: nil, lea_pct: nil, state_pct: nil, delta: nil}

  defp snapshot_to_all_subjects_avg(map) do
    %{
      school_pct: to_float(map["school_pct"]),
      lea_pct: to_float(map["lea_pct"]),
      state_pct: to_float(map["state_pct"]),
      delta: to_float(map["delta"])
    }
  end
end
