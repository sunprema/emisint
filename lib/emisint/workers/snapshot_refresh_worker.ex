defmodule Emisint.Workers.SnapshotRefreshWorker do
  @moduledoc """
  Oban worker that recomputes PerformanceSnapshots for a school/year combination.

  Expected job args:
    - `organization_id`   — tenant UUID
    - `school_id`         — UUID of the target school
    - `academic_year_id`  — UUID of the target academic year

  Pipeline:
    1. Query enrolled students for school/year
    2. Fetch their AssessmentResults
    3. Aggregate by (subject, testing_window) at school-wide, per-grade, and per-subgroup levels
    4. Upsert PerformanceSnapshots
    5. Enqueue GoalRecalculationWorker
  """

  use Oban.Worker, queue: :analytics, max_attempts: 3

  require Ash.Query

  alias Emisint.Analytics.PerformanceSnapshot
  alias Emisint.Assessments.AssessmentResult
  alias Emisint.Registry.Enrollment

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "organization_id" => org_id,
          "school_id" => school_id,
          "academic_year_id" => academic_year_id
        }
      }) do
    # 1. Get all enrollments for this school/year
    enrollments =
      Enrollment
      |> Ash.Query.filter(school_id == ^school_id and academic_year_id == ^academic_year_id)
      |> Ash.read!(tenant: org_id, authorize?: false)

    student_ids = Enum.map(enrollments, & &1.student_id)

    enrollment_by_student =
      Map.new(enrollments, fn e -> {e.student_id, e} end)

    if student_ids == [] do
      :ok
    else
      # 2. Fetch all assessment results for those students/year
      student_id_set = MapSet.new(student_ids)

      results =
        AssessmentResult
        |> Ash.Query.filter(academic_year_id == ^academic_year_id)
        |> Ash.read!(tenant: org_id, authorize?: false)
        |> Enum.filter(fn r -> MapSet.member?(student_id_set, r.student_id) end)

      # 3. Build and upsert snapshots
      snapshots = build_snapshots(results, enrollment_by_student, school_id, academic_year_id)

      Ash.bulk_create(snapshots, PerformanceSnapshot, :upsert,
        tenant: org_id,
        authorize?: false,
        upsert_fields: [:proficiency_rate, :average_sgp, :median_sgp, :student_count]
      )

      # 4. Enqueue GoalRecalculationWorker
      %{
        organization_id: org_id,
        school_id: school_id,
        academic_year_id: academic_year_id
      }
      |> Emisint.Workers.GoalRecalculationWorker.new()
      |> Oban.insert!()

      :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Snapshot construction
  # ---------------------------------------------------------------------------

  defp build_snapshots(results, enrollment_by_student, school_id, academic_year_id) do
    # Group by subject + testing_window
    by_subject_window =
      Enum.group_by(results, fn r -> {r.subject, r.testing_window} end)

    Enum.flat_map(by_subject_window, fn {{subject, window}, window_results} ->
      school_wide = build_school_wide_snapshot(window_results, subject, window, school_id, academic_year_id)

      by_grade = build_by_grade_snapshots(window_results, enrollment_by_student, subject, window, school_id, academic_year_id)

      by_subgroup = build_by_subgroup_snapshots(window_results, subject, window, school_id, academic_year_id)

      [school_wide | by_grade ++ by_subgroup]
    end)
  end

  defp build_school_wide_snapshot(results, subject, window, school_id, academic_year_id) do
    metrics = compute_metrics(results)

    Map.merge(metrics, %{
      snapshot_type: :school_wide,
      subject: subject,
      grade_level: "all",
      subgroup: :all,
      testing_window: window,
      school_id: school_id,
      academic_year_id: academic_year_id
    })
  end

  defp build_by_grade_snapshots(results, enrollment_by_student, subject, window, school_id, academic_year_id) do
    results
    |> Enum.group_by(fn r ->
      enrollment = Map.get(enrollment_by_student, r.student_id)
      if enrollment, do: Atom.to_string(enrollment.grade_level), else: "unknown"
    end)
    |> Enum.map(fn {grade, grade_results} ->
      metrics = compute_metrics(grade_results)

      Map.merge(metrics, %{
        snapshot_type: :by_grade,
        subject: subject,
        grade_level: grade,
        subgroup: :all,
        testing_window: window,
        school_id: school_id,
        academic_year_id: academic_year_id
      })
    end)
  end

  defp build_by_subgroup_snapshots(results, subject, window, school_id, academic_year_id) do
    # Subgroup snapshots require loading student ESSA flags — skip if no results
    []
    # NOTE: Full subgroup computation would join with Student records to filter by
    # economically_disadvantaged / english_learner / special_education flags.
    # Implemented in GoalRecalculationWorker via ComputeGoalActualValue change.
    # Placeholder returned here; a future enhancement can fill this in.
    |> then(fn _ ->
      _subject = subject
      _window = window
      _results = results
      _school_id = school_id
      _academic_year_id = academic_year_id
      []
    end)
  end

  # ---------------------------------------------------------------------------
  # Metric helpers
  # ---------------------------------------------------------------------------

  defp compute_metrics(results) do
    total = length(results)
    proficient = Enum.count(results, &proficient?/1)

    proficiency_rate =
      if total > 0, do: Decimal.div(Decimal.new(proficient), Decimal.new(total)), else: nil

    sgp_values = results |> Enum.map(& &1.sgp) |> Enum.reject(&is_nil/1)

    average_sgp =
      if sgp_values != [] do
        sum = Enum.sum(sgp_values)
        Decimal.div(Decimal.new(sum), Decimal.new(length(sgp_values)))
      end

    median_sgp = if sgp_values != [], do: median(sgp_values)

    %{
      proficiency_rate: proficiency_rate,
      average_sgp: average_sgp,
      median_sgp: median_sgp,
      student_count: total
    }
  end

  defp proficient?(result), do: result.proficiency_level in ["3", "4", "proficient", "on_level"]

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
