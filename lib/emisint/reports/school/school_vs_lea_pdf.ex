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
    snapshot =
      MdeSchoolVsLeaSnapshot
      |> Ash.Query.for_read(:by_building_and_year, %{
        building_code: building_code,
        school_year: year
      })
      |> Ash.read_one!(authorize?: false)

    enrollment = load_enrollment_data(building_code, year)
    sat_results = load_sat_data(building_code, year)
    entity_details = load_entity_details(building_code)

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
          entity_details: entity_details
        }

      snap ->
        subjects = snapshot_to_subjects(snap.subject_comparison)
        grades = snapshot_to_grades(snap.grade_breakdown)
        all_subjects_avg = snapshot_to_all_subjects_avg(snap.all_subjects_avg)

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

  defp load_entity_details(building_code) do
    record =
      MdeEntityMaster
      |> Ash.Query.filter(entity_code == ^building_code)
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

  defp load_sat_data(building_code, year) do
    MdeSatResult
    |> Ash.Query.filter(
      building_code == ^building_code and school_year == ^year and rollup_level == :building
    )
    |> Ash.Query.sort(:subgroup)
    |> Ash.read!(authorize?: false)
    |> Enum.map(fn row ->
      %{
        subgroup: row.subgroup || "All Students",
        num_assessed: row.math_num_assessed,
        math_percent_ready: decimal_to_float(row.math_percent_ready),
        reading_percent_ready: decimal_to_float(row.reading_percent_ready),
        english_percent_ready: decimal_to_float(row.english_percent_ready),
        ebrw_percent_ready: decimal_to_float(row.ebrw_percent_ready),
        all_subject_percent_ready: decimal_to_float(row.all_subject_percent_ready)
      }
    end)
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

      %{
        grade: "Grade #{grade}",
        school_ela: to_float(row["school_ela"]),
        lea_ela: to_float(row["lea_ela"]),
        state_ela: to_float(row["state_ela"]),
        ela_delta: to_float(row["ela_delta"]),
        school_math: to_float(row["school_math"]),
        lea_math: to_float(row["lea_math"]),
        state_math: to_float(row["state_math"]),
        math_delta: to_float(row["math_delta"])
      }
    end)
  end

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
