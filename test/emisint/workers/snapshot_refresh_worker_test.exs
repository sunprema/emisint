defmodule Emisint.Workers.SnapshotRefreshWorkerTest do
  use Emisint.DataCase, async: false
  use Oban.Testing, repo: Emisint.Repo

  alias Emisint.Accounts.School
  alias Emisint.Analytics.PerformanceSnapshot
  alias Emisint.Assessments.AssessmentResult
  alias Emisint.Registry.{AcademicYear, Enrollment, Student}
  alias Emisint.Workers.SnapshotRefreshWorker

  defp org_id, do: Ash.UUID.generate()

  defp setup_org(oid) do
    school =
      Ash.create!(School,
        %{name: "Snapshot School", mde_district_code: "25010", mde_building_code: "08001"},
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

  defp create_enrolled_student(oid, school, year, uic, grade \\ :g5) do
    student =
      Ash.create!(Student,
        %{uic: uic, first_name: "Student", last_name: uic},
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

  defp create_result(oid, student, year, attrs \\ %{}) do
    Ash.create!(AssessmentResult,
      Map.merge(
        %{
          student_id: student.id,
          academic_year_id: year.id,
          assessment_type: :nwea_map,
          subject: "math",
          testing_window: :fall,
          proficiency_level: "3",
          sgp: 55
        },
        attrs
      ),
      tenant: oid,
      authorize?: false
    )
  end

  defp run_worker(oid, school, year) do
    SnapshotRefreshWorker.perform(%Oban.Job{
      args: %{
        "organization_id" => oid,
        "school_id" => school.id,
        "academic_year_id" => year.id
      }
    })
  end

  describe "when no students are enrolled" do
    test "returns :ok without creating snapshots" do
      oid = org_id()
      {school, year} = setup_org(oid)

      assert :ok = run_worker(oid, school, year)
      assert Ash.read!(PerformanceSnapshot, tenant: oid, authorize?: false) == []
    end
  end

  describe "with enrolled students and assessment results" do
    test "creates a school-wide snapshot" do
      oid = org_id()
      {school, year} = setup_org(oid)
      student = create_enrolled_student(oid, school, year, "M001")
      create_result(oid, student, year)

      assert :ok = run_worker(oid, school, year)

      snaps = Ash.read!(PerformanceSnapshot, tenant: oid, authorize?: false)
      school_wide = Enum.find(snaps, fn s -> s.snapshot_type == :school_wide end)
      assert school_wide != nil
      assert school_wide.subject == "math"
      assert school_wide.testing_window == :fall
      assert school_wide.student_count == 1
    end

    test "creates a by_grade snapshot" do
      oid = org_id()
      {school, year} = setup_org(oid)
      student = create_enrolled_student(oid, school, year, "M001", :g5)
      create_result(oid, student, year)

      assert :ok = run_worker(oid, school, year)

      snaps = Ash.read!(PerformanceSnapshot, tenant: oid, authorize?: false)
      by_grade = Enum.find(snaps, fn s -> s.snapshot_type == :by_grade end)
      assert by_grade != nil
      assert by_grade.grade_level == "g5"
    end

    test "computes proficiency_rate correctly" do
      oid = org_id()
      {school, year} = setup_org(oid)

      # 2 proficient (level "3"), 1 not proficient (level "1")
      for {uic, level} <- [{"M001", "3"}, {"M002", "3"}, {"M003", "1"}] do
        student = create_enrolled_student(oid, school, year, uic)
        create_result(oid, student, year, %{proficiency_level: level})
      end

      assert :ok = run_worker(oid, school, year)

      snaps = Ash.read!(PerformanceSnapshot, tenant: oid, authorize?: false)
      school_wide = Enum.find(snaps, fn s -> s.snapshot_type == :school_wide end)

      expected_rate = Decimal.div(Decimal.new(2), Decimal.new(3))
      assert Decimal.equal?(school_wide.proficiency_rate, expected_rate)
    end

    test "enqueues GoalRecalculationWorker" do
      oid = org_id()
      {school, year} = setup_org(oid)
      student = create_enrolled_student(oid, school, year, "M001")
      create_result(oid, student, year)

      assert :ok = run_worker(oid, school, year)

      assert_enqueued(
        worker: Emisint.Workers.GoalRecalculationWorker,
        args: %{
          "organization_id" => oid,
          "school_id" => school.id,
          "academic_year_id" => year.id
        }
      )
    end

    test "computing median_sgp for an even number of results" do
      oid = org_id()
      {school, year} = setup_org(oid)

      for {uic, sgp} <- [{"M001", 40}, {"M002", 60}] do
        student = create_enrolled_student(oid, school, year, uic)
        create_result(oid, student, year, %{sgp: sgp})
      end

      assert :ok = run_worker(oid, school, year)

      snaps = Ash.read!(PerformanceSnapshot, tenant: oid, authorize?: false)
      school_wide = Enum.find(snaps, fn s -> s.snapshot_type == :school_wide end)

      assert Decimal.equal?(school_wide.median_sgp, Decimal.from_float(50.0))
    end
  end
end
