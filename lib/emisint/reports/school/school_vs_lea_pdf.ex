defmodule Emisint.Reports.School.SchoolVsLeaPdf do
  @template_path "priv/typst/school/school_vs_lea.typ"

  require Ash.Query

  alias Emisint.Assessments.{MdeEntityMaster, MdeStateAssessmentResult}

  @subjects ["ELA", "Mathematics", "Science", "Social Studies"]

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
    padded_code = String.pad_leading(building_code, 5, "0")

    entity =
      MdeEntityMaster
      |> Ash.Query.filter(entity_code == ^padded_code)
      |> Ash.read_one!(authorize?: false)

    lea_district_code = entity && entity.entity_geographic_lea_district_code
    school_name = (entity && entity.entity_official_name) || building_code

    school_results =
      MdeStateAssessmentResult
      |> Ash.Query.filter(
        rollup_level == :building and
          report_category == "All Students" and
          school_year == ^year and
          mde_building.building_code == ^building_code
      )
      |> Ash.read!(authorize?: false)

    {lea_results, lea_district_name} =
      if lea_district_code do
        rows =
          MdeStateAssessmentResult
          |> Ash.Query.filter(
            rollup_level == :district and
              report_category == "All Students" and
              school_year == ^year and
              mde_district.district_code == ^lea_district_code
          )
          |> Ash.Query.load(:mde_district)
          |> Ash.read!(authorize?: false)

        name =
          case rows do
            [first | _] ->
              (first.mde_district && first.mde_district.district_name) || lea_district_code

            [] ->
              lea_district_code
          end

        {rows, name}
      else
        {[], nil}
      end

    state_results =
      MdeStateAssessmentResult
      |> Ash.Query.filter(
        rollup_level == :isd and
          report_category == "All Students" and
          school_year == ^year and
          mde_isd.isd_code == "0"
      )
      |> Ash.read!(authorize?: false)

    subjects = build_subject_comparison(school_results, lea_results, state_results)
    grades = build_grade_comparison(school_results, lea_results, state_results)

    above_lea = Enum.count(subjects, fn s -> s.school_pct && s.lea_pct && s.delta >= 0 end)
    below_lea = Enum.count(subjects, fn s -> s.school_pct && s.lea_pct && s.delta < 0 end)

    above_state =
      Enum.count(subjects, fn s ->
        s.school_pct && s.state_pct && s.school_vs_state_delta && s.school_vs_state_delta >= 0
      end)

    %{
      school: %{
        name: school_name,
        building_code: building_code,
        report_date: Date.utc_today() |> Calendar.strftime("%b %d, %Y")
      },
      school_year: year,
      lea: %{
        district_code: lea_district_code || "",
        district_name: lea_district_name || ""
      },
      above_lea: above_lea,
      below_lea: below_lea,
      above_state: above_state,
      grades_compared: length(grades),
      subjects: subjects,
      grade_breakdown: grades
    }
  end

  # --- Aggregation ---

  defp build_subject_comparison(school_rows, lea_rows, state_rows) do
    Enum.map(@subjects, fn subject ->
      school_subj = Enum.filter(school_rows, &(&1.subject == subject))
      lea_subj = Enum.filter(lea_rows, &(&1.subject == subject))
      state_subj = Enum.filter(state_rows, &(&1.subject == subject))

      school_pct = weighted_proficiency_float(school_subj)
      lea_pct = weighted_proficiency_float(lea_subj)
      state_pct = weighted_proficiency_float(state_subj)
      delta = if school_pct && lea_pct, do: Float.round(school_pct - lea_pct, 1), else: nil

      school_vs_state_delta =
        if school_pct && state_pct, do: Float.round(school_pct - state_pct, 1), else: nil

      %{
        subject: subject,
        school_pct: school_pct,
        lea_pct: lea_pct,
        state_pct: state_pct,
        delta: delta,
        school_vs_state_delta: school_vs_state_delta
      }
    end)
  end

  defp build_grade_comparison(school_rows, lea_rows, state_rows) do
    school_grades =
      school_rows
      |> Enum.reject(&(is_nil(&1.grade_content_tested) or &1.grade_content_tested == "All"))
      |> Enum.group_by(& &1.grade_content_tested)

    lea_grades =
      lea_rows
      |> Enum.reject(&(is_nil(&1.grade_content_tested) or &1.grade_content_tested == "All"))
      |> Enum.group_by(& &1.grade_content_tested)

    state_grades =
      state_rows
      |> Enum.reject(&(is_nil(&1.grade_content_tested) or &1.grade_content_tested == "All"))
      |> Enum.group_by(& &1.grade_content_tested)

    all_grades =
      (Map.keys(school_grades) ++ Map.keys(lea_grades))
      |> Enum.uniq()
      |> Enum.sort()

    Enum.map(all_grades, fn grade ->
      s = Map.get(school_grades, grade, [])
      l = Map.get(lea_grades, grade, [])
      st = Map.get(state_grades, grade, [])

      school_ela = weighted_proficiency_float(Enum.filter(s, &(&1.subject == "ELA")))
      lea_ela = weighted_proficiency_float(Enum.filter(l, &(&1.subject == "ELA")))
      state_ela = weighted_proficiency_float(Enum.filter(st, &(&1.subject == "ELA")))
      school_math = weighted_proficiency_float(Enum.filter(s, &(&1.subject == "Mathematics")))
      lea_math = weighted_proficiency_float(Enum.filter(l, &(&1.subject == "Mathematics")))
      state_math = weighted_proficiency_float(Enum.filter(st, &(&1.subject == "Mathematics")))

      %{
        grade: "Grade #{grade}",
        school_ela: school_ela,
        lea_ela: lea_ela,
        state_ela: state_ela,
        ela_delta: if(school_ela && lea_ela, do: Float.round(school_ela - lea_ela, 1), else: nil),
        school_math: school_math,
        lea_math: lea_math,
        state_math: state_math,
        math_delta:
          if(school_math && lea_math, do: Float.round(school_math - lea_math, 1), else: nil)
      }
    end)
  end

  defp weighted_proficiency_float([]), do: nil

  defp weighted_proficiency_float(rows) do
    {total_assessed, total_prof} =
      Enum.reduce(rows, {0, 0}, fn r, {assessed, prof} ->
        {
          assessed + (r.number_assessed || 0),
          prof + (r.total_advanced || 0) + (r.total_proficient || 0)
        }
      end)

    if total_assessed > 0, do: Float.round(total_prof / total_assessed * 100, 1), else: nil
  end
end
