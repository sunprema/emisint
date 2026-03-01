defmodule Emisint.Reports.School.SchoolVsLeaPdf do
  @template_path "priv/typst/school/school_vs_lea.typ"

  require Ash.Query

  alias Emisint.Assessments.MdeSchoolVsLeaSnapshot

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
          grade_breakdown: []
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
          grade_breakdown: grades
        }
    end
  end

  # --- Snapshot → PDF data shape converters ---

  defp snapshot_to_subjects(nil), do: []

  defp snapshot_to_subjects(list) do
    Enum.map(list, fn row ->
      %{
        subject: row["subject"],
        school_pct: row["school_pct"],
        lea_pct: row["lea_pct"],
        state_pct: row["state_pct"],
        delta: row["delta"],
        school_vs_state_delta: row["school_vs_state_delta"]
      }
    end)
  end

  defp snapshot_to_grades(nil), do: []

  defp snapshot_to_grades(list) do
    Enum.map(list, fn row ->
      grade = row["grade"]

      %{
        grade: "Grade #{grade}",
        school_ela: row["school_ela"],
        lea_ela: row["lea_ela"],
        state_ela: row["state_ela"],
        ela_delta: row["ela_delta"],
        school_math: row["school_math"],
        lea_math: row["lea_math"],
        state_math: row["state_math"],
        math_delta: row["math_delta"]
      }
    end)
  end

  defp snapshot_to_all_subjects_avg(nil),
    do: %{school_pct: nil, lea_pct: nil, state_pct: nil, delta: nil}

  defp snapshot_to_all_subjects_avg(map) do
    %{
      school_pct: map["school_pct"],
      lea_pct: map["lea_pct"],
      state_pct: map["state_pct"],
      delta: map["delta"]
    }
  end
end
