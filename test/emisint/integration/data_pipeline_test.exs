defmodule Emisint.Integration.DataPipelineTest do
  @moduledoc """
  End-to-end integration test covering the full academic data pipeline:

    Student → Enrollment → AssessmentResult
      → SnapshotRefreshWorker → PerformanceSnapshot
      → GoalRecalculationWorker → GoalEvaluation → InterventionTrigger

  Each test runs the full chain and asserts the final state at every layer.
  """

  use Emisint.DataCase, async: false
  use Oban.Testing, repo: Emisint.Repo

  require Ash.Query

  alias Emisint.Accounts.School
  alias Emisint.Analytics.{InterventionTrigger, PerformanceSnapshot}
  alias Emisint.Assessments.AssessmentResult
  alias Emisint.Compliance.{GoalEvaluation, Schedule71Goal}
  alias Emisint.Registry.{AcademicYear, Enrollment, Student}
  alias Emisint.Workers.{GoalRecalculationWorker, SnapshotRefreshWorker}

  # ── Setup helpers ─────────────────────────────────────────────────────────

  defp gen_oid, do: Ash.UUID.generate()

  defp create_base(oid) do
    school =
      Ash.create!(School,
        %{name: "Pipeline Test Academy", mde_district_code: "77001", mde_building_code: "77001-1"},
        tenant: oid,
        authorize?: false
      )

    year =
      Ash.create!(AcademicYear,
        %{label: "2024-2025", start_date: ~D[2024-09-03], end_date: ~D[2025-06-13]},
        tenant: oid,
        authorize?: false
      )

    {school, year}
  end

  defp create_student_with_enrollment(oid, uic, school, year, grade \\ :g5) do
    student =
      Ash.create!(Student,
        %{uic: uic, first_name: "Test", last_name: "Student"},
        tenant: oid,
        authorize?: false
      )

    Ash.create!(Enrollment,
      %{
        grade_level: grade,
        enrolled_at: ~D[2024-09-03],
        student_id: student.id,
        school_id: school.id,
        academic_year_id: year.id
      },
      tenant: oid,
      authorize?: false
    )

    student
  end

  defp create_result(oid, student, year, attrs \\ %{}) do
    Ash.create!(AssessmentResult,
      Map.merge(
        %{
          assessment_type: :m_step,
          subject: "math",
          testing_window: :spring,
          student_id: student.id,
          academic_year_id: year.id
        },
        attrs
      ),
      tenant: oid,
      authorize?: false
    )
  end

  defp create_goal(oid, school, attrs \\ %{}) do
    Ash.create!(Schedule71Goal,
      Map.merge(
        %{
          title: "Test Goal",
          goal_type: :proficiency_threshold,
          subject: "math",
          testing_window: :spring,
          target_value: Decimal.new("0.65"),
          comparison_operator: :gte,
          school_id: school.id
        },
        attrs
      ),
      tenant: oid,
      authorize?: false
    )
  end

  defp run_snapshot_worker(oid, school, year) do
    SnapshotRefreshWorker.perform(%Oban.Job{
      args: %{
        "organization_id" => oid,
        "school_id" => school.id,
        "academic_year_id" => year.id
      }
    })
  end

  defp run_goal_worker(oid, school, year) do
    GoalRecalculationWorker.perform(%Oban.Job{
      args: %{
        "organization_id" => oid,
        "school_id" => school.id,
        "academic_year_id" => year.id
      }
    })
  end

  # ── SnapshotRefreshWorker tests ──────────────────────────────────────────

  describe "SnapshotRefreshWorker" do
    test "creates school_wide snapshot with correct proficiency rate" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      # 7 proficient / 10 total = 0.7
      Enum.each(1..7, fn i ->
        s = create_student_with_enrollment(oid, "S#{i}", school, year)
        create_result(oid, s, year, %{proficiency_level: "3"})
      end)

      Enum.each(8..10, fn i ->
        s = create_student_with_enrollment(oid, "S#{i}", school, year)
        create_result(oid, s, year, %{proficiency_level: "1"})
      end)

      assert :ok = run_snapshot_worker(oid, school, year)

      snapshots =
        PerformanceSnapshot
        |> Ash.Query.filter(school_id == ^school.id and snapshot_type == :school_wide)
        |> Ash.read!(tenant: oid, authorize?: false)

      assert length(snapshots) == 1
      snap = hd(snapshots)
      assert snap.student_count == 10
      assert Decimal.compare(snap.proficiency_rate, Decimal.new("0.7")) == :eq
    end

    test "creates by_grade snapshots segregated by grade level" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      # 3 students in g5, 2 students in g6
      Enum.each(1..3, fn i ->
        s = create_student_with_enrollment(oid, "G5_#{i}", school, year, :g5)
        create_result(oid, s, year, %{proficiency_level: "3", sgp: 50})
      end)

      Enum.each(1..2, fn i ->
        s = create_student_with_enrollment(oid, "G6_#{i}", school, year, :g6)
        create_result(oid, s, year, %{proficiency_level: "2", sgp: 40})
      end)

      assert :ok = run_snapshot_worker(oid, school, year)

      by_grade =
        PerformanceSnapshot
        |> Ash.Query.filter(school_id == ^school.id and snapshot_type == :by_grade)
        |> Ash.read!(tenant: oid, authorize?: false)

      grades = Enum.map(by_grade, & &1.grade_level) |> Enum.sort()
      assert "g5" in grades
      assert "g6" in grades

      g5_snap = Enum.find(by_grade, &(&1.grade_level == "g5"))
      assert g5_snap.student_count == 3
      assert Decimal.compare(g5_snap.proficiency_rate, Decimal.new("1")) == :eq

      g6_snap = Enum.find(by_grade, &(&1.grade_level == "g6"))
      assert g6_snap.student_count == 2
      assert Decimal.compare(g6_snap.proficiency_rate, Decimal.new("0")) == :eq
    end

    test "computes median SGP correctly" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      # SGPs: [30, 50, 70] → median = 50
      Enum.each([{"A", 30}, {"B", 50}, {"C", 70}], fn {id, sgp} ->
        s = create_student_with_enrollment(oid, id, school, year)
        create_result(oid, s, year, %{sgp: sgp, proficiency_level: "3"})
      end)

      assert :ok = run_snapshot_worker(oid, school, year)

      snap =
        PerformanceSnapshot
        |> Ash.Query.filter(school_id == ^school.id and snapshot_type == :school_wide)
        |> Ash.read!(tenant: oid, authorize?: false)
        |> hd()

      assert Decimal.compare(snap.median_sgp, Decimal.new("50")) == :eq
    end

    test "returns :ok with no snapshots when school has no enrolled students" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      assert :ok = run_snapshot_worker(oid, school, year)

      snapshots = Ash.read!(PerformanceSnapshot, tenant: oid, authorize?: false)
      assert snapshots == []
    end

    test "enqueues GoalRecalculationWorker after completion" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      s = create_student_with_enrollment(oid, "S1", school, year)
      create_result(oid, s, year, %{proficiency_level: "3"})

      assert :ok = run_snapshot_worker(oid, school, year)

      assert_enqueued(
        worker: Emisint.Workers.GoalRecalculationWorker,
        args: %{
          "organization_id" => oid,
          "school_id" => school.id,
          "academic_year_id" => year.id
        }
      )
    end
  end

  # ── GoalRecalculationWorker tests ────────────────────────────────────────

  describe "GoalRecalculationWorker" do
    test "creates GoalEvaluation with :meets status when goal is met" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      # 8/10 proficient → 80% ≥ 65% target
      Enum.each(1..8, fn i ->
        s = create_student_with_enrollment(oid, "P#{i}", school, year)
        create_result(oid, s, year, %{proficiency_level: "3"})
      end)

      Enum.each(9..10, fn i ->
        s = create_student_with_enrollment(oid, "P#{i}", school, year)
        create_result(oid, s, year, %{proficiency_level: "1"})
      end)

      _goal = create_goal(oid, school, %{target_value: Decimal.new("0.65")})

      assert :ok = run_goal_worker(oid, school, year)

      evals = Ash.read!(GoalEvaluation, tenant: oid, authorize?: false)
      assert length(evals) == 1
      eval = hd(evals)
      assert eval.status in [:meets, :exceeds]
    end

    test "creates GoalEvaluation with :below status when goal is missed" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      # 4/10 proficient → 40% < 65% target
      Enum.each(1..4, fn i ->
        s = create_student_with_enrollment(oid, "P#{i}", school, year)
        create_result(oid, s, year, %{proficiency_level: "3"})
      end)

      Enum.each(5..10, fn i ->
        s = create_student_with_enrollment(oid, "P#{i}", school, year)
        create_result(oid, s, year, %{proficiency_level: "1"})
      end)

      _goal = create_goal(oid, school, %{target_value: Decimal.new("0.65")})

      assert :ok = run_goal_worker(oid, school, year)

      evals = Ash.read!(GoalEvaluation, tenant: oid, authorize?: false)
      assert hd(evals).status == :below
    end

    test "creates InterventionTrigger for :below evaluations" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      # Only 3/10 proficient → well below target
      Enum.each(1..3, fn i ->
        s = create_student_with_enrollment(oid, "P#{i}", school, year)
        create_result(oid, s, year, %{proficiency_level: "3"})
      end)

      Enum.each(4..10, fn i ->
        s = create_student_with_enrollment(oid, "P#{i}", school, year)
        create_result(oid, s, year, %{proficiency_level: "1"})
      end)

      _goal = create_goal(oid, school, %{target_value: Decimal.new("0.65")})

      assert :ok = run_goal_worker(oid, school, year)

      triggers = Ash.read!(InterventionTrigger, tenant: oid, authorize?: false)
      assert length(triggers) == 1

      trigger = hd(triggers)
      assert trigger.trigger_type == :goal_at_risk
      assert trigger.severity == :high
      assert trigger.status == :active
    end

    test "does NOT create InterventionTrigger for :meets or :exceeds evaluations" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      # All 10 proficient → well above target
      Enum.each(1..10, fn i ->
        s = create_student_with_enrollment(oid, "P#{i}", school, year)
        create_result(oid, s, year, %{proficiency_level: "4"})
      end)

      _goal = create_goal(oid, school, %{target_value: Decimal.new("0.65")})

      assert :ok = run_goal_worker(oid, school, year)

      triggers = Ash.read!(InterventionTrigger, tenant: oid, authorize?: false)
      assert triggers == []
    end

    test "resolves an existing trigger when goal improves from :below to :meets" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      goal = create_goal(oid, school, %{target_value: Decimal.new("0.65")})

      # First run: below target (3/10 proficient)
      students =
        Enum.map(1..10, fn i ->
          s = create_student_with_enrollment(oid, "P#{i}", school, year)
          level = if i <= 3, do: "3", else: "1"
          create_result(oid, s, year, %{proficiency_level: level})
          s
        end)

      assert :ok = run_goal_worker(oid, school, year)
      assert length(Ash.read!(InterventionTrigger, tenant: oid, authorize?: false)) == 1

      # Add more results to push proficiency above target
      Enum.each(Enum.drop(students, 3), fn student ->
        existing =
          AssessmentResult
          |> Ash.Query.filter(student_id == ^student.id)
          |> Ash.read!(tenant: oid, authorize?: false)
          |> hd()

        Ash.update!(existing, %{proficiency_level: "3"}, tenant: oid, authorize?: false)
      end)

      # Second run: now meets target (10/10 proficient)
      assert :ok = run_goal_worker(oid, school, year)

      triggers = Ash.read!(InterventionTrigger, tenant: oid, authorize?: false)
      resolved_triggers = Enum.filter(triggers, &(&1.status == :resolved))
      assert length(resolved_triggers) == 1
    end

    test "handles multiple goals per school independently" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      # Data: 8/10 proficient, SGP median = 35 (below 50th)
      Enum.each([{"A", "3", 40}, {"B", "3", 38}, {"C", "4", 62}, {"D", "3", 45},
                 {"E", "4", 58}, {"F", "3", 50}, {"G", "4", 72}, {"H", "3", 35},
                 {"I", "1", 20}, {"J", "2", 25}], fn {id, level, sgp} ->
        s = create_student_with_enrollment(oid, id, school, year)
        create_result(oid, s, year, %{proficiency_level: level, sgp: sgp})
      end)

      _proficiency_goal =
        create_goal(oid, school, %{
          goal_type: :proficiency_threshold,
          target_value: Decimal.new("0.65")
        })

      _sgp_goal =
        create_goal(oid, school, %{
          goal_type: :sgp_median,
          title: "SGP Goal",
          target_value: Decimal.new("50")
        })

      assert :ok = run_goal_worker(oid, school, year)

      evals = Ash.read!(GoalEvaluation, tenant: oid, authorize?: false)
      assert length(evals) == 2

      statuses = Enum.map(evals, & &1.status) |> Enum.sort()
      # proficiency 8/10=80% → meets/exceeds; SGP median 40 → below
      assert :below in statuses
      assert Enum.any?(statuses, &(&1 in [:meets, :exceeds]))
    end
  end

  # ── Full pipeline end-to-end ──────────────────────────────────────────────

  describe "full pipeline: assessment data → snapshot → evaluation → trigger" do
    test "complete chain produces correct outcomes for a passing school" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      # 9/12 proficient (75%), median SGP = 54 — both goals should meet
      data = [
        {"S1", "4", 68}, {"S2", "3", 55}, {"S3", "4", 72},
        {"S4", "3", 54}, {"S5", "2", 38}, {"S6", "4", 61},
        {"S7", "3", 58}, {"S8", "1", 28}, {"S9", "4", 66},
        {"S10", "3", 52}, {"S11", "4", 70}, {"S12", "2", 35}
      ]

      Enum.each(data, fn {uic, level, sgp} ->
        s = create_student_with_enrollment(oid, uic, school, year)
        create_result(oid, s, year, %{proficiency_level: level, sgp: sgp})
      end)

      _proficiency_goal =
        create_goal(oid, school, %{
          goal_type: :proficiency_threshold,
          target_value: Decimal.new("0.65"),
          exceeds_threshold: Decimal.new("0.80")
        })

      _sgp_goal =
        create_goal(oid, school, %{
          goal_type: :sgp_median,
          title: "SGP Goal",
          target_value: Decimal.new("50"),
          exceeds_threshold: Decimal.new("60")
        })

      # Step 1: Run snapshot refresh
      assert :ok = run_snapshot_worker(oid, school, year)

      # Assert snapshots exist
      snapshots = Ash.read!(PerformanceSnapshot, tenant: oid, authorize?: false)
      assert length(snapshots) > 0

      school_wide = Enum.find(snapshots, &(&1.snapshot_type == :school_wide))
      assert school_wide != nil
      assert school_wide.student_count == 12
      # 9/12 = 0.75
      assert Decimal.compare(school_wide.proficiency_rate, Decimal.new("0.75")) == :eq
      # median of [28,35,38,52,54,55,58,61,66,68,70,72] = (55+58)/2 = 56.5
      assert Decimal.compare(school_wide.median_sgp, Decimal.new("56.5")) == :eq

      # Step 2: Run goal recalculation
      assert :ok = run_goal_worker(oid, school, year)

      # Assert evaluations
      evals = Ash.read!(GoalEvaluation, tenant: oid, authorize?: false)
      assert length(evals) == 2

      for eval <- evals do
        assert eval.status in [:meets, :exceeds]
      end

      # Assert no intervention triggers (all goals met)
      triggers = Ash.read!(InterventionTrigger, tenant: oid, authorize?: false)
      assert triggers == []
    end

    test "complete chain produces :below evaluation and trigger for at-risk school" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      # 4/10 proficient (40%), low SGP — both goals should be below
      data = [
        {"S1", "3", 30}, {"S2", "3", 35}, {"S3", "3", 38}, {"S4", "4", 42},
        {"S5", "1", 20}, {"S6", "2", 25}, {"S7", "1", 18}, {"S8", "2", 22},
        {"S9", "1", 28}, {"S10", "2", 31}
      ]

      Enum.each(data, fn {uic, level, sgp} ->
        s = create_student_with_enrollment(oid, uic, school, year)
        create_result(oid, s, year, %{proficiency_level: level, sgp: sgp})
      end)

      _goal = create_goal(oid, school, %{target_value: Decimal.new("0.65")})

      assert :ok = run_snapshot_worker(oid, school, year)
      assert :ok = run_goal_worker(oid, school, year)

      # Evaluation should be :below
      evals = Ash.read!(GoalEvaluation, tenant: oid, authorize?: false)
      assert hd(evals).status == :below

      # Intervention trigger should be created
      triggers = Ash.read!(InterventionTrigger, tenant: oid, authorize?: false)
      assert length(triggers) == 1
      assert hd(triggers).severity == :high
    end
  end
end
