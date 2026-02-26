defmodule Emisint.Compliance.Changes.ComputeGoalActualValue do
  use Ash.Resource.Change

  @moduledoc """
  Core APM computation engine.

  For a given Schedule71Goal + AcademicYear combination, queries enrolled students,
  fetches their AssessmentResults, computes the relevant metric for the goal_type,
  and sets :actual_value, :data_points_count, :status, :evaluated_at plus
  snapshots of the goal's threshold fields on the GoalEvaluation changeset.
  """

  alias Emisint.Assessments.{AssessmentResult, CompetitorData}
  alias Emisint.Compliance.Calculations.EvaluateGoalStatus
  alias Emisint.Compliance.Schedule71Goal
  alias Emisint.Registry.{AcademicYear, Enrollment, Student}

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    goal_id = Ash.Changeset.get_attribute(changeset, :schedule71_goal_id)
    year_id = Ash.Changeset.get_attribute(changeset, :academic_year_id)
    tenant = changeset.tenant

    goal =
      Ash.get!(Schedule71Goal, goal_id,
        tenant: tenant,
        authorize?: false,
        load: [:school]
      )

    # Snapshot goal thresholds into the evaluation record
    changeset =
      changeset
      |> Ash.Changeset.force_change_attribute(:target_value, goal.target_value)
      |> Ash.Changeset.force_change_attribute(:comparison_operator, goal.comparison_operator)
      |> Ash.Changeset.force_change_attribute(:exceeds_threshold, goal.exceeds_threshold)
      |> Ash.Changeset.force_change_attribute(:approaching_threshold, goal.approaching_threshold)
      |> Ash.Changeset.force_change_attribute(:evaluated_at, DateTime.utc_now())

    student_ids = fetch_student_ids(goal, year_id, tenant)

    {actual_value, data_points_count} = compute_metric(goal, student_ids, year_id, tenant)

    status =
      EvaluateGoalStatus.evaluate(
        actual_value,
        goal.target_value,
        goal.comparison_operator,
        goal.exceeds_threshold,
        goal.approaching_threshold
      )

    changeset
    |> Ash.Changeset.force_change_attribute(:actual_value, actual_value)
    |> Ash.Changeset.force_change_attribute(:data_points_count, data_points_count)
    |> Ash.Changeset.force_change_attribute(:status, status)
  end

  # ---------------------------------------------------------------------------
  # Student selection
  # ---------------------------------------------------------------------------

  defp fetch_student_ids(goal, year_id, tenant) do
    query =
      Enrollment
      |> Ash.Query.filter(school_id == ^goal.school_id and academic_year_id == ^year_id)

    query =
      if goal.grade_levels != [] do
        grade_atoms = Enum.map(goal.grade_levels, &String.to_atom/1)
        Ash.Query.filter(query, grade_level in ^grade_atoms)
      else
        query
      end

    base_ids =
      query
      |> Ash.read!(tenant: tenant, authorize?: false)
      |> Enum.map(& &1.student_id)

    filter_by_subgroup(base_ids, goal.subgroup, tenant)
  end

  defp filter_by_subgroup([], _subgroup, _tenant), do: []

  defp filter_by_subgroup(ids, subgroup, _tenant) when subgroup in [nil, :all], do: ids

  defp filter_by_subgroup(ids, subgroup, tenant) do
    Student
    |> Ash.Query.filter(id in ^ids)
    |> filter_subgroup_field(subgroup)
    |> Ash.read!(tenant: tenant, authorize?: false)
    |> Enum.map(& &1.id)
  end

  defp filter_subgroup_field(query, :economically_disadvantaged),
    do: Ash.Query.filter(query, economically_disadvantaged == true)

  defp filter_subgroup_field(query, :english_learner),
    do: Ash.Query.filter(query, english_learner == true)

  defp filter_subgroup_field(query, :special_education),
    do: Ash.Query.filter(query, special_education == true)

  # ---------------------------------------------------------------------------
  # Metric computation — one clause per goal_type
  # ---------------------------------------------------------------------------

  defp compute_metric(_goal, [], _year_id, _tenant), do: {nil, 0}

  defp compute_metric(%{goal_type: :sgp_median} = goal, student_ids, year_id, tenant) do
    results = fetch_assessment_results(goal, student_ids, year_id, tenant)
    sgp_values = results |> Enum.map(& &1.sgp) |> Enum.reject(&is_nil/1)

    case sgp_values do
      [] -> {nil, 0}
      values -> {median(values), length(values)}
    end
  end

  defp compute_metric(%{goal_type: :proficiency_threshold} = goal, student_ids, year_id, tenant) do
    results = fetch_assessment_results(goal, student_ids, year_id, tenant)
    total = length(results)

    if total == 0 do
      {nil, 0}
    else
      proficient = Enum.count(results, &proficient?/1)
      {Decimal.div(Decimal.new(proficient), Decimal.new(total)), total}
    end
  end

  defp compute_metric(%{goal_type: :growth_target} = goal, student_ids, year_id, tenant) do
    results = fetch_assessment_results(goal, student_ids, year_id, tenant)
    trackable = Enum.reject(results, &is_nil(&1.growth_target))
    total = length(trackable)

    if total == 0 do
      {nil, 0}
    else
      on_track =
        Enum.count(trackable, fn r ->
          !is_nil(r.scale_score) &&
            Decimal.compare(r.scale_score, r.growth_target) in [:gt, :eq]
        end)

      {Decimal.div(Decimal.new(on_track), Decimal.new(total)), total}
    end
  end

  defp compute_metric(%{goal_type: :outperform_district} = goal, student_ids, year_id, tenant) do
    results = fetch_assessment_results(goal, student_ids, year_id, tenant)
    total = length(results)

    if total == 0 do
      {nil, 0}
    else
      proficient = Enum.count(results, &proficient?/1)
      school_rate = Decimal.div(Decimal.new(proficient), Decimal.new(total))

      year = Ash.get!(AcademicYear, year_id, tenant: tenant, authorize?: false)

      district_results =
        CompetitorData
        |> Ash.Query.filter(
          mde_district_code == ^goal.school.mde_district_code and
            subject == ^goal.subject and
            academic_year_label == ^year.label
        )
        |> Ash.read!(authorize?: false)

      case district_results do
        [data | _] -> {Decimal.sub(school_rate, data.proficiency_rate), total}
        [] -> {nil, total}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp fetch_assessment_results(goal, student_ids, year_id, tenant) do
    query =
      AssessmentResult
      |> Ash.Query.filter(
        student_id in ^student_ids and
          academic_year_id == ^year_id and
          subject == ^goal.subject and
          testing_window == ^goal.testing_window
      )

    query =
      if goal.assessment_type do
        Ash.Query.filter(query, assessment_type == ^goal.assessment_type)
      else
        query
      end

    Ash.read!(query, tenant: tenant, authorize?: false)
  end

  # M-STEP: levels 3 (Proficient) and 4 (Advanced) are at/above proficiency.
  # For binary systems: "proficient" and "on_level" map to the same concept.
  defp proficient?(result) do
    result.proficiency_level in ["3", "4", "proficient", "on_level"]
  end

  defp median(values) do
    sorted = Enum.sort(values)
    count = length(sorted)
    mid = div(count, 2)

    if rem(count, 2) == 0 do
      avg = (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
      Decimal.from_float(avg)
    else
      Decimal.new(Enum.at(sorted, mid))
    end
  end
end
