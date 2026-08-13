defmodule Emisint.Reports.School.SchoolSnapshot do
  @moduledoc """
  Shared REAL-data loaders for school-level PDF reports (entity identity,
  enrollment, resident districts, School Index, SGP, weighted state-assessment
  proficiency). Extracted from `PerformanceReportPdf` so every report that
  needs this same current-year snapshot — currently `PerformanceReportPdf`
  and `BoardSummaryPdf` — reads from one source instead of two independently
  drifting copies of the same MDE queries (see `PLAN_betterPDF.md` Phase 1.1).

  Does not include anything that's still SAMPLE/placeholder (board members,
  contract terms, mission text, multi-year trends, SSS peer roster) — those
  stay local to whichever report needs them.
  """

  require Ash.Query

  alias Emisint.Assessments.{
    MdeCompositeResidentDistrict,
    MdeEntityMaster,
    MdeEnrollmentResult,
    MdeSchoolIndexResult,
    MdeSgpResult,
    MdeStateAssessmentResult
  }

  @doc """
  Loads the current-year real-data snapshot for a school: entity identity,
  enrollment, resident districts, School Index/participation, mean SGP,
  weighted state-assessment proficiency, and the real half of the
  performance-overview ratings (academic achievement/growth).
  """
  def load(building_code, year) do
    entity_task = Task.async(fn -> load_entity(building_code) end)
    enrollment_task = Task.async(fn -> load_enrollment(building_code, year) end)
    school_index_task = Task.async(fn -> load_school_index(building_code, year) end)
    sgp_task = Task.async(fn -> load_sgp(building_code, year) end)
    proficiency_task = Task.async(fn -> load_proficiency(building_code, year) end)

    entity = Task.await(entity_task, :infinity)
    enrollment = Task.await(enrollment_task, :infinity)
    school_index = Task.await(school_index_task, :infinity)
    sgp = Task.await(sgp_task, :infinity)
    proficiency = Task.await(proficiency_task, :infinity)

    %{
      entity: entity,
      enrollment: enrollment,
      resident_districts: load_resident_districts(entity.district_code),
      school_index: school_index,
      sgp: sgp,
      proficiency: proficiency,
      performance_overview: build_performance_overview(proficiency, sgp)
    }
  end

  # Real half of the performance-overview ratings — academic achievement and
  # growth, both derived from real weighted proficiency / mean SGP.
  # Compliance/Financial Reporting Condition have no backing resource at all
  # and stay caller-side (SAMPLE, `PerformanceReportPdf`-only).
  defp build_performance_overview(proficiency, sgp) do
    avg_prof =
      [proficiency.school_ela, proficiency.school_math]
      |> Enum.reject(&is_nil/1)
      |> avg()

    avg_growth =
      [sgp.ela, sgp.math]
      |> Enum.reject(&is_nil/1)
      |> avg()

    %{
      academic_achievement: rating_for(avg_prof),
      academic_growth: rating_for(avg_growth)
    }
  end

  def rating_for(nil), do: "insufficient_data"
  def rating_for(v) when v >= 70, do: "exceeds"
  def rating_for(v) when v >= 50, do: "meets"
  def rating_for(v) when v >= 35, do: "approaching"
  def rating_for(_v), do: "below"

  defp avg([]), do: nil
  defp avg(list), do: Enum.sum(list) / length(list)

  # --- Entity / enrollment / resident districts -------------------------------

  @entity_select [
    :entity_official_name,
    :entity_physical_street,
    :entity_physical_city,
    :entity_physical_state,
    :entity_physical_zip4,
    :entity_authorized_grades,
    :entity_actual_grades,
    :entity_open_date,
    :isd_official_name,
    :entity_chartering_agency_name,
    :district_code
  ]

  def load_entity(building_code) do
    record =
      MdeEntityMaster
      |> Ash.Query.filter(entity_code == ^building_code)
      |> Ash.Query.select(@entity_select)
      |> Ash.read_one!(authorize?: false)

    case record do
      nil ->
        %{
          name: building_code,
          street: "",
          city: "",
          state: "",
          zip: "",
          authorized_grades: "",
          actual_grades: "",
          year_opened: "",
          isd_name: "",
          chartering_agency_name: "",
          district_code: nil
        }

      rec ->
        %{
          name: rec.entity_official_name || building_code,
          street: rec.entity_physical_street || "",
          city: rec.entity_physical_city || "",
          state: rec.entity_physical_state || "",
          zip: rec.entity_physical_zip4 || "",
          authorized_grades: rec.entity_authorized_grades || "",
          actual_grades: rec.entity_actual_grades || "",
          year_opened: rec.entity_open_date || "",
          isd_name: rec.isd_official_name || "",
          chartering_agency_name: rec.entity_chartering_agency_name || "",
          district_code: rec.district_code
        }
    end
  end

  def load_enrollment(building_code, year) do
    record =
      MdeEnrollmentResult
      |> Ash.Query.filter(
        building_code == ^building_code and school_year == ^year and rollup_level == :building
      )
      |> Ash.read_one!(authorize?: false)

    case record do
      nil ->
        %{
          total: nil,
          econ_pct: nil,
          sped_pct: nil,
          ell_pct: nil,
          by_grade: %{}
        }

      rec ->
        %{
          total: rec.total_enrollment,
          econ_pct: safe_pct(rec.economic_disadvantaged_enrollment, rec.total_enrollment),
          sped_pct: safe_pct(rec.special_education_enrollment, rec.total_enrollment),
          ell_pct: safe_pct(rec.english_language_learners_enrollment, rec.total_enrollment),
          by_grade: %{
            "K" => rec.kindergarten_enrollment,
            "1" => rec.grade_1_enrollment,
            "2" => rec.grade_2_enrollment,
            "3" => rec.grade_3_enrollment,
            "4" => rec.grade_4_enrollment,
            "5" => rec.grade_5_enrollment,
            "6" => rec.grade_6_enrollment,
            "7" => rec.grade_7_enrollment,
            "8" => rec.grade_8_enrollment
          }
        }
    end
  end

  def load_resident_districts(nil), do: []

  def load_resident_districts(district_code) do
    MdeCompositeResidentDistrict
    |> Ash.Query.filter(charter_district_code == ^district_code)
    |> Ash.read!(authorize?: false)
    |> Enum.group_by(& &1.resident_entity_name)
    |> Enum.map(fn {name, rows} ->
      {name, Enum.reduce(rows, 0, &(&2 + (&1.nonresident_students_enrolled || 0)))}
    end)
    |> Enum.reject(fn {_name, total} -> total <= 0 end)
    |> Enum.sort_by(fn {_name, total} -> -total end)
    |> collapse_to_top(2)
  end

  defp collapse_to_top(rows, n) do
    {top, rest} = Enum.split(rows, n)
    total = Enum.reduce(rows, 0, fn {_, v}, acc -> acc + v end)
    others_total = Enum.reduce(rest, 0, fn {_, v}, acc -> acc + v end)

    top_entries =
      Enum.map(top, fn {name, v} -> %{name: name, count: v, pct: safe_pct(v, total)} end)

    if others_total > 0 do
      top_entries ++ [%{name: "Others", count: others_total, pct: safe_pct(others_total, total)}]
    else
      top_entries
    end
  end

  # --- School Index / SGP / proficiency ---------------------------------------

  defp to_index_year(year) do
    year
    |> String.replace(" School Year", "")
    |> String.split(" - ")
    |> case do
      [y1, y2] -> "20#{String.trim(y1)}-20#{String.trim(y2)}"
      _ -> year
    end
  end

  def load_school_index(building_code, year) do
    si_year = to_index_year(year)

    MdeSchoolIndexResult
    |> Ash.Query.filter(mde_building.building_code == ^building_code and school_year == ^si_year)
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil ->
        %{overall: nil, subject_participation: nil, support_category_name: nil}

      si ->
        %{
          overall: decimal_to_float(si.overall_index),
          subject_participation: decimal_to_float(si.subject_participation_index),
          support_category_name: si.support_category_name
        }
    end
  rescue
    _ -> %{overall: nil, subject_participation: nil, support_category_name: nil}
  end

  @sgp_subjects %{"Mathematics" => :math, "English Language Arts" => :ela}

  def load_sgp(building_code, year) do
    rows =
      MdeSgpResult
      |> Ash.Query.filter(
        mde_building.building_code == ^building_code and
          school_year == ^year and
          testing_group == "All Students" and
          grade == "All Grades"
      )
      |> Ash.read!(authorize?: false)

    Enum.reduce(rows, %{ela: nil, math: nil}, fn row, acc ->
      case Map.get(@sgp_subjects, row.subject) do
        nil -> acc
        key -> Map.put(acc, key, decimal_to_float(row.mean_sgp))
      end
    end)
  rescue
    _ -> %{ela: nil, math: nil}
  end

  @proficiency_subjects %{"Mathematics" => :school_math, "ELA" => :school_ela}
  @state_proficiency_subjects %{"Mathematics" => :state_math, "ELA" => :state_ela}

  def load_proficiency(building_code, year) do
    school_task =
      Task.async(fn ->
        MdeStateAssessmentResult
        |> Ash.Query.filter(
          rollup_level == :building and
            mde_building.building_code == ^building_code and
            school_year == ^year and
            report_category == "All Students" and
            grade_content_tested != "All"
        )
        |> Ash.read!(authorize?: false)
      end)

    state_task =
      Task.async(fn ->
        MdeStateAssessmentResult
        |> Ash.Query.filter(
          rollup_level == :isd and
            mde_isd.isd_code == "0" and
            school_year == ^year and
            report_category == "All Students" and
            grade_content_tested != "All"
        )
        |> Ash.read!(authorize?: false)
      end)

    school_rows = Task.await(school_task, :infinity)
    state_rows = Task.await(state_task, :infinity)

    base = %{school_ela: nil, school_math: nil, state_ela: nil, state_math: nil}

    base
    |> merge_weighted_proficiency(school_rows, @proficiency_subjects)
    |> merge_weighted_proficiency(state_rows, @state_proficiency_subjects)
  rescue
    _ -> %{school_ela: nil, school_math: nil, state_ela: nil, state_math: nil}
  end

  defp merge_weighted_proficiency(acc, rows, subject_map) do
    Enum.reduce(subject_map, acc, fn {mde_subject, key}, acc ->
      value =
        rows
        |> Enum.filter(&(&1.subject == mde_subject))
        |> weighted_proficiency()

      Map.put(acc, key, value)
    end)
  end

  defp weighted_proficiency([]), do: nil

  defp weighted_proficiency(rows) do
    {total_assessed, total_prof} =
      rows
      |> Enum.reject(& &1.percent_met_suppressed)
      |> Enum.reduce({0, 0.0}, fn r, {assessed, prof} ->
        pct = if r.percent_met, do: Decimal.to_float(r.percent_met), else: 0.0
        n = r.number_assessed || 0
        {assessed + n, prof + pct * n / 100.0}
      end)

    if total_assessed > 0, do: Float.round(total_prof / total_assessed * 100.0, 1), else: nil
  end

  defp decimal_to_float(nil), do: nil
  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp decimal_to_float(v) when is_float(v), do: v

  defp safe_pct(num, den) when is_integer(num) and is_integer(den) and den > 0,
    do: Float.round(num / den * 100, 1)

  defp safe_pct(_, _), do: nil
end
