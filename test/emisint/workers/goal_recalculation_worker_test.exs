defmodule Emisint.Workers.GoalRecalculationWorkerTest do
  use Emisint.DataCase, async: false
  use Oban.Testing, repo: Emisint.Repo

  alias Emisint.Accounts.School
  alias Emisint.Analytics.InterventionTrigger
  alias Emisint.Assessments.AssessmentResult
  alias Emisint.Compliance.{GoalEvaluation, Schedule71Goal}
  alias Emisint.Registry.{AcademicYear, Enrollment, Student}
  alias Emisint.Workers.GoalRecalculationWorker

  require Ash.Query

  defp org_id, do: Ash.UUID.generate()

  defp setup_base(oid) do
    school =
      Ash.create!(School,
        %{name: "Goal Academy", mde_district_code: "25010", mde_building_code: "08001"},
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

  defp create_goal(oid, school, attrs \\ %{}) do
    Ash.create!(Schedule71Goal,
      Map.merge(
        %{
          title: "Math Proficiency 70%",
          goal_type: :proficiency_threshold,
          subject: "math",
          testing_window: :fall,
          target_value: Decimal.new("0.70"),
          comparison_operator: :gte,
          school_id: school.id
        },
        attrs
      ),
      tenant: oid,
      authorize?: false
    )
  end

  defp create_enrolled_student(oid, school, year, uic, grade \\ :g5) do
    student =
      Ash.create!(Student,
        %{uic: uic, first_name: "Test", last_name: uic},
        tenant: oid,
        authorize?: false
      )

    Ash.create!(Enrollment,
      %{student_id: student.id, school_id: school.id, academic_year_id: year.id, grade_level: grade, enrolled_at: Date.utc_today()},
      tenant: oid,
      authorize?: false
    )

    student
  end

  defp create_result(oid, student, year, proficiency_level \\ "3") do
    Ash.create!(AssessmentResult,
      %{
        student_id: student.id,
        academic_year_id: year.id,
        assessment_type: :nwea_map,
        subject: "math",
        testing_window: :fall,
        proficiency_level: proficiency_level,
        sgp: 50
      },
      tenant: oid,
      authorize?: false
    )
  end

  defp run_worker(oid, school, year) do
    GoalRecalculationWorker.perform(%Oban.Job{
      args: %{
        "organization_id" => oid,
        "school_id" => school.id,
        "academic_year_id" => year.id
      }
    })
  end

  describe "when no goals exist" do
    test "returns :ok without errors" do
      oid = org_id()
      {school, year} = setup_base(oid)

      assert :ok = run_worker(oid, school, year)
    end
  end

  describe "GoalEvaluation upsert" do
    test "creates a GoalEvaluation for each Schedule71Goal" do
      oid = org_id()
      {school, year} = setup_base(oid)
      _goal = create_goal(oid, school)

      # 3 of 3 students proficient → meets 70% threshold
      for uic <- ["M001", "M002", "M003"] do
        student = create_enrolled_student(oid, school, year, uic)
        create_result(oid, student, year, "3")
      end

      assert :ok = run_worker(oid, school, year)

      evals = Ash.read!(GoalEvaluation, tenant: oid, authorize?: false)
      assert length(evals) == 1
      eval = hd(evals)
      assert eval.status in [:meets, :exceeds]
    end

    test "evaluation is idempotent — reruns produce one GoalEvaluation" do
      oid = org_id()
      {school, year} = setup_base(oid)
      _goal = create_goal(oid, school)

      student = create_enrolled_student(oid, school, year, "M001")
      create_result(oid, student, year, "3")

      assert :ok = run_worker(oid, school, year)
      assert :ok = run_worker(oid, school, year)

      evals = Ash.read!(GoalEvaluation, tenant: oid, authorize?: false)
      assert length(evals) == 1
    end
  end

  describe "InterventionTrigger sync — below threshold" do
    test "creates an active trigger when goal status is :below" do
      oid = org_id()
      {school, year} = setup_base(oid)
      _goal = create_goal(oid, school)

      # 0 of 3 proficient → below 70% target
      for uic <- ["M001", "M002", "M003"] do
        student = create_enrolled_student(oid, school, year, uic)
        create_result(oid, student, year, "1")
      end

      assert :ok = run_worker(oid, school, year)

      triggers = Ash.read!(InterventionTrigger, tenant: oid, authorize?: false)
      assert length(triggers) == 1
      trigger = hd(triggers)
      assert trigger.status == :active
      assert trigger.trigger_type == :goal_at_risk
      assert trigger.severity == :high
    end
  end

  describe "InterventionTrigger sync — meets/exceeds threshold" do
    test "resolves existing active trigger when goal is now met" do
      oid = org_id()
      {school, year} = setup_base(oid)
      goal = create_goal(oid, school)

      # First run: 0% proficient → trigger created
      for uic <- ["M001", "M002"] do
        student = create_enrolled_student(oid, school, year, uic)
        create_result(oid, student, year, "1")
      end

      assert :ok = run_worker(oid, school, year)
      triggers_before = Ash.read!(InterventionTrigger, tenant: oid, authorize?: false)
      assert length(triggers_before) == 1
      assert hd(triggers_before).status == :active

      # Update results to 100% proficient so goal is now met
      results = Ash.read!(AssessmentResult, tenant: oid, authorize?: false)

      Enum.each(results, fn r ->
        Ash.update!(r, %{proficiency_level: "4"}, tenant: oid, authorize?: false)
      end)

      assert :ok = run_worker(oid, school, year)

      evals = Ash.read!(GoalEvaluation, tenant: oid, authorize?: false)
      eval = Enum.find(evals, fn e -> e.schedule71_goal_id == goal.id end)
      assert eval.status in [:meets, :exceeds]

      triggers_after = Ash.read!(InterventionTrigger, tenant: oid, authorize?: false)
      assert length(triggers_after) == 1
      resolved = hd(triggers_after)
      assert resolved.status == :resolved
    end
  end
end
