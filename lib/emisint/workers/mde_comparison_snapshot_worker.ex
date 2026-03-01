defmodule Emisint.Workers.MdeComparisonSnapshotWorker do
  @moduledoc """
  Oban worker that pre-computes MdeDistrictSnapshot and MdeSchoolVsLeaSnapshot
  rows for a given school year, then bulk-upserts them so LiveViews and PDF
  reports can perform a single indexed read instead of complex aggregation.

  ## Job args
    - `school_year` — e.g. "2022-2023"

  ## Enqueuing
      %{"school_year" => "2022-2023"}
      |> Emisint.Workers.MdeComparisonSnapshotWorker.new()
      |> Oban.insert!()
  """

  use Oban.Worker, queue: :analytics, max_attempts: 3

  require Ash.Query
  require Logger

  alias Emisint.Assessments.{
    MdeDistrictSnapshot,
    MdeEntityMaster,
    MdeSchoolVsLeaSnapshot,
    MdeStateAssessmentResult
  }

  @subjects ["ELA", "Mathematics", "Science", "Social Studies"]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"school_year" => year}}) do
    Logger.info("[MdeComparisonSnapshotWorker] Starting for #{year}")

    # 1. Fetch building-level results for year
    building_results =
      MdeStateAssessmentResult
      |> Ash.Query.filter(
        school_year == ^year and
          report_category == "All Students" and
          rollup_level == :building
      )
      |> Ash.Query.load(mde_building: [mde_district: :mde_isd])
      |> Ash.read!(authorize?: false)

    # 2. Fetch district-level results for year
    district_results =
      MdeStateAssessmentResult
      |> Ash.Query.filter(
        school_year == ^year and
          report_category == "All Students" and
          rollup_level == :district
      )
      |> Ash.Query.load(:mde_district)
      |> Ash.read!(authorize?: false)

    # 3. Fetch state-level results (isd_code "0" = Michigan state aggregate)
    state_results =
      MdeStateAssessmentResult
      |> Ash.Query.filter(
        school_year == ^year and
          report_category == "All Students" and
          rollup_level == :isd and
          mde_isd.isd_code == "0"
      )
      |> Ash.read!(authorize?: false)

    # 4. Fetch all entity master records for building → LEA lookup
    entity_masters = MdeEntityMaster |> Ash.read!(authorize?: false)

    # Phase A: District snapshots
    district_snapshots = build_district_snapshots(building_results, year)

    Ash.bulk_create(district_snapshots, MdeDistrictSnapshot, :upsert,
      authorize?: false,
      return_errors?: true,
      upsert_fields: [
        :district_name,
        :entity_type,
        :isd_name,
        :buildings,
        :total_assessed,
        :ela_pct,
        :math_pct,
        :avg_total_proficient,
        :all_subjects,
        :grade_breakdown,
        :proficiency_dist
      ]
    )

    Logger.info("[MdeComparisonSnapshotWorker] #{length(district_snapshots)} district snapshots upserted for #{year}")

    # Phase B: School vs LEA snapshots
    school_snapshots =
      build_school_vs_lea_snapshots(building_results, district_results, state_results, entity_masters, year)

    Ash.bulk_create(school_snapshots, MdeSchoolVsLeaSnapshot, :upsert,
      authorize?: false,
      return_errors?: true,
      upsert_fields: [
        :school_name,
        :lea_district_code,
        :lea_district_name,
        :above_lea,
        :below_lea,
        :above_state,
        :grades_compared,
        :no_lea_found,
        :no_results,
        :no_lea_results,
        :no_state_results,
        :subject_comparison,
        :all_subjects_avg,
        :grade_breakdown
      ]
    )

    Logger.info("[MdeComparisonSnapshotWorker] #{length(school_snapshots)} school vs LEA snapshots upserted for #{year}")

    Phoenix.PubSub.broadcast(
      Emisint.PubSub,
      "mde_import",
      {:mde_comparison_snapshots_ready, year}
    )

    :ok
  end

  # ---------------------------------------------------------------------------
  # Phase A — district snapshots
  # ---------------------------------------------------------------------------

  defp build_district_snapshots(building_results, year) do
    building_results
    |> Enum.group_by(fn r -> r.mde_building && r.mde_building.mde_district end)
    |> Enum.reject(fn {district, _} -> is_nil(district) end)
    |> Enum.map(fn {district, rows} ->
      ela_rows = Enum.filter(rows, &(&1.subject == "ELA"))
      math_rows = Enum.filter(rows, &(&1.subject == "Mathematics"))
      buildings = rows |> Enum.map(& &1.mde_building_id) |> Enum.uniq() |> length()
      isd_name = district.mde_isd && district.mde_isd.isd_name

      total_assessed =
        ela_rows
        |> Enum.filter(&(&1.grade_content_tested == "All"))
        |> Enum.map(&(&1.number_assessed || 0))
        |> Enum.sum()

      ela_pct = weighted_proficiency_float(ela_rows)
      math_pct = weighted_proficiency_float(math_rows)

      all_subjects =
        Map.new(@subjects, fn subject ->
          subj_rows = Enum.filter(rows, &(&1.subject == subject))
          {subject, weighted_proficiency_float(subj_rows)}
        end)

      avg_total_proficient =
        all_subjects
        |> Map.values()
        |> avg_across_values()

      %{
        district_code: district.district_code,
        school_year: year,
        district_name: district.district_name,
        entity_type: district.entity_type,
        isd_name: isd_name,
        buildings: buildings,
        total_assessed: total_assessed,
        ela_pct: ela_pct,
        math_pct: math_pct,
        avg_total_proficient: avg_total_proficient,
        all_subjects: all_subjects,
        grade_breakdown: build_grade_breakdown_maps(rows),
        proficiency_dist: compute_proficiency_dist_map(rows)
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Phase B — school vs LEA snapshots
  # ---------------------------------------------------------------------------

  defp build_school_vs_lea_snapshots(building_results, district_results, state_results, entity_masters, year) do
    # Build entity_master_map: building_code (padded + unpadded) → entity info
    entity_master_map =
      Enum.reduce(entity_masters, %{}, fn em, acc ->
        padded = em.entity_code
        unpadded = String.trim_leading(padded, "0")

        info = %{
          lea_district_code: em.entity_geographic_lea_district_code,
          school_name: em.entity_official_name
        }

        acc
        |> Map.put(padded, info)
        |> Map.put(unpadded, info)
      end)

    # Build district_results_map: district_code → list of rows
    district_results_map =
      district_results
      |> Enum.group_by(fn r -> r.mde_district && r.mde_district.district_code end)
      |> Map.delete(nil)

    # Get all unique building codes
    building_codes =
      building_results
      |> Enum.map(fn r -> r.mde_building && r.mde_building.building_code end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    Enum.map(building_codes, fn building_code ->
      padded_code = String.pad_leading(building_code, 5, "0")

      entity_info =
        Map.get(entity_master_map, padded_code) ||
          Map.get(entity_master_map, building_code)

      lea_district_code = entity_info && entity_info.lea_district_code
      school_name = (entity_info && entity_info.school_name) || building_code

      school_rows =
        Enum.filter(building_results, fn r ->
          r.mde_building && r.mde_building.building_code == building_code
        end)

      lea_rows = Map.get(district_results_map, lea_district_code, [])

      lea_district_name =
        case lea_rows do
          [first | _] ->
            (first.mde_district && first.mde_district.district_name) || lea_district_code

          [] ->
            lea_district_code
        end

      subject_comparison = build_subject_comparison_maps(school_rows, lea_rows, state_results)
      all_subjects_avg = build_all_subjects_avg_map(subject_comparison)
      grade_breakdown = build_grade_comparison_maps(school_rows, lea_rows, state_results)

      above_lea =
        Enum.count(subject_comparison, fn s ->
          s["school_pct"] && s["lea_pct"] && (s["delta"] || 0) >= 0
        end)

      below_lea =
        Enum.count(subject_comparison, fn s ->
          s["school_pct"] && s["lea_pct"] && (s["delta"] || 0) < 0
        end)

      above_state =
        Enum.count(subject_comparison, fn s ->
          s["school_pct"] && s["state_pct"] && (s["school_vs_state_delta"] || 0) >= 0
        end)

      %{
        building_code: building_code,
        school_year: year,
        school_name: school_name,
        lea_district_code: lea_district_code,
        lea_district_name: lea_district_name,
        above_lea: above_lea,
        below_lea: below_lea,
        above_state: above_state,
        grades_compared: length(grade_breakdown),
        no_lea_found: is_nil(lea_district_code),
        no_results: school_rows == [],
        no_lea_results: lea_rows == [],
        no_state_results: state_results == [],
        subject_comparison: subject_comparison,
        all_subjects_avg: all_subjects_avg,
        grade_breakdown: grade_breakdown
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Aggregation helpers
  # ---------------------------------------------------------------------------

  defp build_grade_breakdown_maps(rows) do
    rows
    |> Enum.reject(fn r ->
      is_nil(r.grade_content_tested) or r.grade_content_tested == "All"
    end)
    |> Enum.group_by(& &1.grade_content_tested)
    |> Enum.map(fn {grade, grade_rows} ->
      ela = Enum.filter(grade_rows, &(&1.subject == "ELA"))
      math = Enum.filter(grade_rows, &(&1.subject == "Mathematics"))
      students = ela |> Enum.map(&(&1.number_assessed || 0)) |> Enum.sum()

      %{
        "grade" => grade,
        "ela" => weighted_proficiency_float(ela),
        "math" => weighted_proficiency_float(math),
        "students" => students
      }
    end)
    |> Enum.sort_by(& &1["grade"])
  end

  defp compute_proficiency_dist_map(rows) do
    all_grade_rows = Enum.filter(rows, &(&1.grade_content_tested == "All"))

    {total_adv, total_prof, total_partly, total_not, total_n} =
      Enum.reduce(all_grade_rows, {0, 0, 0, 0, 0}, fn r, {adv, prof, partly, not_p, n} ->
        {
          adv + (r.total_advanced || 0),
          prof + (r.total_proficient || 0),
          partly + (r.total_partially_proficient || 0),
          not_p + (r.total_not_proficient || 0),
          n + (r.number_assessed || 0)
        }
      end)

    if total_n > 0 do
      %{
        "advanced" => Float.round(total_adv / total_n * 100, 1),
        "proficient" => Float.round(total_prof / total_n * 100, 1),
        "partially" => Float.round(total_partly / total_n * 100, 1),
        "not_proficient" => Float.round(total_not / total_n * 100, 1)
      }
    else
      nil
    end
  end

  defp build_subject_comparison_maps(school_rows, lea_rows, state_rows) do
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
        "subject" => subject,
        "school_pct" => school_pct,
        "lea_pct" => lea_pct,
        "state_pct" => state_pct,
        "delta" => delta,
        "school_vs_state_delta" => school_vs_state_delta
      }
    end)
  end

  defp build_all_subjects_avg_map(subject_comparison) do
    avg_school = avg_across_values(Enum.map(subject_comparison, & &1["school_pct"]))
    avg_lea = avg_across_values(Enum.map(subject_comparison, & &1["lea_pct"]))
    avg_state = avg_across_values(Enum.map(subject_comparison, & &1["state_pct"]))
    delta = if avg_school && avg_lea, do: Float.round(avg_school - avg_lea, 1), else: nil

    %{
      "school_pct" => avg_school,
      "lea_pct" => avg_lea,
      "state_pct" => avg_state,
      "delta" => delta
    }
  end

  defp build_grade_comparison_maps(school_rows, lea_rows, state_rows) do
    school_grades =
      school_rows
      |> Enum.reject(fn r ->
        is_nil(r.grade_content_tested) or r.grade_content_tested == "All"
      end)
      |> Enum.group_by(& &1.grade_content_tested)

    lea_grades =
      lea_rows
      |> Enum.reject(fn r ->
        is_nil(r.grade_content_tested) or r.grade_content_tested == "All"
      end)
      |> Enum.group_by(& &1.grade_content_tested)

    state_grades =
      state_rows
      |> Enum.reject(fn r ->
        is_nil(r.grade_content_tested) or r.grade_content_tested == "All"
      end)
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
        "grade" => grade,
        "school_ela" => school_ela,
        "lea_ela" => lea_ela,
        "state_ela" => state_ela,
        "ela_delta" => if(school_ela && lea_ela, do: Float.round(school_ela - lea_ela, 1), else: nil),
        "school_math" => school_math,
        "lea_math" => lea_math,
        "state_math" => state_math,
        "math_delta" =>
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

  defp avg_across_values(values) do
    non_nil = Enum.reject(values, &is_nil/1)
    if non_nil == [], do: nil, else: Float.round(Enum.sum(non_nil) / length(non_nil), 1)
  end
end
