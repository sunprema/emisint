defmodule Emisint.Integration.CsvImportTest do
  @moduledoc """
  End-to-end integration test covering the full CSV import pipeline:

    CSV rows → CsvImportWorker → AssessmentResult (bulk upsert)
      → SnapshotRefreshWorker → PerformanceSnapshot
      → GoalRecalculationWorker → GoalEvaluation → InterventionTrigger

  Workers are called directly (Oban is in :manual testing mode).
  """

  use Emisint.DataCase, async: false
  use Oban.Testing, repo: Emisint.Repo

  require Ash.Query

  alias Emisint.Accounts.School
  alias Emisint.Analytics.{DataSyncLog, InterventionTrigger, PerformanceSnapshot}
  alias Emisint.Assessments.AssessmentResult
  alias Emisint.Compliance.{GoalEvaluation, Schedule71Goal}
  alias Emisint.Registry.{AcademicYear, Enrollment, Student}
  alias Emisint.Workers.{CsvImportWorker, GoalRecalculationWorker, SnapshotRefreshWorker}

  # ── Setup helpers ───────────────────────────────────────────────────────────

  defp gen_oid, do: Ash.UUID.generate()

  defp create_base(oid) do
    school =
      Ash.create!(School,
        %{name: "CSV Pipeline Academy", mde_district_code: "99001", mde_building_code: "99001-1"},
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

  defp create_student(oid, uic) do
    Ash.create!(Student,
      %{uic: uic, first_name: "Test", last_name: "Student"},
      tenant: oid,
      authorize?: false
    )
  end

  defp enroll_student(oid, student, school, year, grade \\ :g5) do
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
  end

  # Builds a realistic NWEA MAP CSV row map (pre-parsed, matching CsvImportWorker's expected keys)
  defp nwea_row(uic, rit_score, sgp, subject \\ "Mathematics") do
    %{
      "StudentID" => uic,
      "Subject" => subject,
      "TermName" => "Fall 2024",
      "TestRITScore" => "#{rit_score}",
      "TestPercentile" => "#{div(sgp, 2) + 20}",
      "ConditionalSGP" => "#{sgp}",
      "TestDate" => "2024-10-15"
    }
  end

  defp run_csv_import(oid, school, year, rows, provider \\ "nwea_map") do
    CsvImportWorker.perform(%Oban.Job{
      args: %{
        "organization_id" => oid,
        "school_id" => school.id,
        "academic_year_id" => year.id,
        "provider_code" => provider,
        "rows" => rows
      }
    })
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

  # Goal matching NWEA MAP fall math import — testing_window and subject must match
  # what CsvImportWorker maps for "nwea_map" / "Fall 2024" / "Mathematics"
  defp create_fall_sgp_goal(oid, school, target) do
    Ash.create!(Schedule71Goal,
      %{
        title: "Fall NWEA MAP Median SGP Goal",
        goal_type: :sgp_median,
        subject: "math",
        testing_window: :fall,
        assessment_type: :nwea_map,
        target_value: Decimal.new("#{target}"),
        comparison_operator: :gte,
        school_id: school.id
      },
      tenant: oid,
      authorize?: false
    )
  end

  # ── CSV import mechanics ────────────────────────────────────────────────────

  describe "CSV import mechanics" do
    test "creates AssessmentResults for enrolled students with matching UICs" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      s1 = create_student(oid, "S1")
      s2 = create_student(oid, "S2")
      enroll_student(oid, s1, school, year)
      enroll_student(oid, s2, school, year)

      rows = [nwea_row("S1", 218, 58), nwea_row("S2", 212, 51)]

      assert :ok = run_csv_import(oid, school, year, rows)

      results = Ash.read!(AssessmentResult, tenant: oid, authorize?: false)
      assert length(results) == 2

      result = hd(results)
      assert result.assessment_type == :nwea_map
      assert result.subject == "math"
      assert result.testing_window == :fall
    end

    test "rows with unknown UICs are skipped; known UICs are still imported" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      student = create_student(oid, "KNOWN_UIC")
      enroll_student(oid, student, school, year)

      rows = [
        nwea_row("KNOWN_UIC", 218, 58),
        nwea_row("UNKNOWN_999", 205, 44),
        nwea_row("ALSO_UNKNOWN", 215, 52)
      ]

      assert :ok = run_csv_import(oid, school, year, rows)

      results = Ash.read!(AssessmentResult, tenant: oid, authorize?: false)
      assert length(results) == 1
      assert hd(results).assessment_type == :nwea_map
    end

    test "DataSyncLog is marked :completed after a successful import" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      student = create_student(oid, "S1")
      enroll_student(oid, student, school, year)

      assert :ok = run_csv_import(oid, school, year, [nwea_row("S1", 215, 54)])

      logs = Ash.read!(DataSyncLog, tenant: oid, authorize?: false)
      assert length(logs) == 1

      log = hd(logs)
      assert log.status == :completed
      assert log.job_type == :csv_import
      assert log.records_processed == 1
      assert log.records_failed == 0
      assert log.completed_at != nil
    end

    test "DataSyncLog metadata records provider_code and total row_count" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      student = create_student(oid, "S1")
      enroll_student(oid, student, school, year)

      # 3 rows submitted — only 1 will be imported (S1 is known; others are unknown)
      rows = [nwea_row("S1", 215, 54), nwea_row("UNKNOWN_1", 200, 30), nwea_row("UNKNOWN_2", 198, 28)]
      assert :ok = run_csv_import(oid, school, year, rows)

      log = Ash.read!(DataSyncLog, tenant: oid, authorize?: false) |> hd()
      # metadata keys are string after JSON round-trip
      assert log.metadata["provider_code"] == "nwea_map"
      assert log.metadata["row_count"] == 3
    end

    test "re-importing the same row updates the record without creating a duplicate" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      student = create_student(oid, "S1")
      enroll_student(oid, student, school, year)

      # First import: SGP = 45
      assert :ok = run_csv_import(oid, school, year, [nwea_row("S1", 212, 45)])

      results_v1 = Ash.read!(AssessmentResult, tenant: oid, authorize?: false)
      assert length(results_v1) == 1
      assert hd(results_v1).sgp == 45

      # Second import: same student, updated SGP = 62
      assert :ok = run_csv_import(oid, school, year, [nwea_row("S1", 220, 62)])

      results_v2 = Ash.read!(AssessmentResult, tenant: oid, authorize?: false)
      # Still one record (upserted, not duplicated)
      assert length(results_v2) == 1
      # SGP updated to new value
      assert hd(results_v2).sgp == 62
    end

    test "SnapshotRefreshWorker is enqueued after successful import" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      student = create_student(oid, "S1")
      enroll_student(oid, student, school, year)

      assert :ok = run_csv_import(oid, school, year, [nwea_row("S1", 215, 54)])

      assert_enqueued(
        worker: SnapshotRefreshWorker,
        args: %{
          "organization_id" => oid,
          "school_id" => school.id,
          "academic_year_id" => year.id
        }
      )
    end
  end

  # ── Snapshot computation after import ──────────────────────────────────────

  describe "snapshot computation after CSV import" do
    test "school_wide snapshot reflects imported SGP and student count" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      # 4 students: SGPs = [40, 50, 60, 70] → median = (50+60)/2 = 55
      sgp_data = [{"A", 40}, {"B", 50}, {"C", 60}, {"D", 70}]

      students =
        Enum.map(sgp_data, fn {uic, _} ->
          s = create_student(oid, uic)
          enroll_student(oid, s, school, year)
          s
        end)

      rows =
        Enum.zip(students, sgp_data)
        |> Enum.map(fn {s, {_uic, sgp}} -> nwea_row(s.uic, 210 + sgp, sgp) end)

      assert :ok = run_csv_import(oid, school, year, rows)
      assert :ok = run_snapshot_worker(oid, school, year)

      snapshots =
        PerformanceSnapshot
        |> Ash.Query.filter(school_id == ^school.id and snapshot_type == :school_wide)
        |> Ash.read!(tenant: oid, authorize?: false)

      assert length(snapshots) == 1

      snap = hd(snapshots)
      assert snap.student_count == 4
      assert snap.subject == "math"
      assert snap.testing_window == :fall
      # Median of [40, 50, 60, 70] = (50 + 60) / 2 = 55
      assert Decimal.compare(snap.median_sgp, Decimal.new("55")) == :eq
    end

    test "by_grade snapshots are created per grade level" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      # 3 students in g5, 2 students in g6
      g5_students =
        Enum.map(1..3, fn i ->
          s = create_student(oid, "G5_#{i}")
          enroll_student(oid, s, school, year, :g5)
          s
        end)

      g6_students =
        Enum.map(1..2, fn i ->
          s = create_student(oid, "G6_#{i}")
          enroll_student(oid, s, school, year, :g6)
          s
        end)

      rows =
        Enum.map(g5_students, fn s -> nwea_row(s.uic, 218, 55) end) ++
          Enum.map(g6_students, fn s -> nwea_row(s.uic, 225, 62) end)

      assert :ok = run_csv_import(oid, school, year, rows)
      assert :ok = run_snapshot_worker(oid, school, year)

      by_grade =
        PerformanceSnapshot
        |> Ash.Query.filter(school_id == ^school.id and snapshot_type == :by_grade)
        |> Ash.read!(tenant: oid, authorize?: false)

      grade_levels = Enum.map(by_grade, & &1.grade_level) |> Enum.sort()
      assert "g5" in grade_levels
      assert "g6" in grade_levels

      g5_snap = Enum.find(by_grade, &(&1.grade_level == "g5"))
      assert g5_snap.student_count == 3

      g6_snap = Enum.find(by_grade, &(&1.grade_level == "g6"))
      assert g6_snap.student_count == 2
    end

    test "re-importing updated data causes snapshot to reflect new values" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      # 3 students; initial SGPs all = 30
      students =
        Enum.map(1..3, fn i ->
          s = create_student(oid, "S#{i}")
          enroll_student(oid, s, school, year)
          s
        end)

      rows_v1 = Enum.map(students, fn s -> nwea_row(s.uic, 200, 30) end)
      assert :ok = run_csv_import(oid, school, year, rows_v1)
      assert :ok = run_snapshot_worker(oid, school, year)

      snap_v1 =
        PerformanceSnapshot
        |> Ash.Query.filter(school_id == ^school.id and snapshot_type == :school_wide)
        |> Ash.read!(tenant: oid, authorize?: false)
        |> hd()

      assert Decimal.compare(snap_v1.median_sgp, Decimal.new("30")) == :eq

      # Re-import with SGPs = 70 for all students
      rows_v2 = Enum.map(students, fn s -> nwea_row(s.uic, 220, 70) end)
      assert :ok = run_csv_import(oid, school, year, rows_v2)
      assert :ok = run_snapshot_worker(oid, school, year)

      snap_v2 =
        PerformanceSnapshot
        |> Ash.Query.filter(school_id == ^school.id and snapshot_type == :school_wide)
        |> Ash.read!(tenant: oid, authorize?: false)
        |> hd()

      assert Decimal.compare(snap_v2.median_sgp, Decimal.new("70")) == :eq
    end
  end

  # ── Full pipeline: CSV → snapshot → goal evaluation ────────────────────────

  describe "full CSV pipeline: import → snapshot → goal evaluation" do
    test "school meeting SGP goal produces no intervention trigger" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      # 6 students with high SGPs: [50, 52, 55, 58, 60, 65] → median = (55+58)/2 = 56.5 ≥ 50
      sgp_values = [50, 52, 55, 58, 60, 65]

      students =
        Enum.map(1..6, fn i ->
          s = create_student(oid, "S#{i}")
          enroll_student(oid, s, school, year)
          s
        end)

      rows = Enum.zip(students, sgp_values) |> Enum.map(fn {s, sgp} -> nwea_row(s.uic, 215 + sgp, sgp) end)

      # Step 1: Import
      assert :ok = run_csv_import(oid, school, year, rows)

      results = Ash.read!(AssessmentResult, tenant: oid, authorize?: false)
      assert length(results) == 6

      log = Ash.read!(DataSyncLog, tenant: oid, authorize?: false) |> hd()
      assert log.status == :completed
      assert log.records_processed == 6

      # Step 2: Refresh snapshots
      assert :ok = run_snapshot_worker(oid, school, year)

      school_wide =
        PerformanceSnapshot
        |> Ash.Query.filter(school_id == ^school.id and snapshot_type == :school_wide)
        |> Ash.read!(tenant: oid, authorize?: false)
        |> hd()

      assert school_wide.student_count == 6
      # Median of [50,52,55,58,60,65] = (55+58)/2 = 56.5
      assert Decimal.compare(school_wide.median_sgp, Decimal.new("56.5")) == :eq

      # Step 3: Evaluate goals
      _goal = create_fall_sgp_goal(oid, school, 50)
      assert :ok = run_goal_worker(oid, school, year)

      evals = Ash.read!(GoalEvaluation, tenant: oid, authorize?: false)
      assert length(evals) == 1
      assert hd(evals).status in [:meets, :exceeds]

      # No intervention triggers — school is on track
      triggers = Ash.read!(InterventionTrigger, tenant: oid, authorize?: false)
      assert triggers == []
    end

    test "school below SGP goal produces an active :high severity trigger" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      # 6 students with low SGPs: [20, 25, 28, 30, 32, 35] → median = (28+30)/2 = 29 < 50
      sgp_values = [20, 25, 28, 30, 32, 35]

      students =
        Enum.map(1..6, fn i ->
          s = create_student(oid, "S#{i}")
          enroll_student(oid, s, school, year)
          s
        end)

      rows = Enum.zip(students, sgp_values) |> Enum.map(fn {s, sgp} -> nwea_row(s.uic, 200 + sgp, sgp) end)

      assert :ok = run_csv_import(oid, school, year, rows)
      assert :ok = run_snapshot_worker(oid, school, year)

      school_wide =
        PerformanceSnapshot
        |> Ash.Query.filter(school_id == ^school.id and snapshot_type == :school_wide)
        |> Ash.read!(tenant: oid, authorize?: false)
        |> hd()

      # Confirm snapshot shows below-target SGP before asserting goal outcome
      assert Decimal.compare(school_wide.median_sgp, Decimal.new("50")) == :lt

      _goal = create_fall_sgp_goal(oid, school, 50)
      assert :ok = run_goal_worker(oid, school, year)

      evals = Ash.read!(GoalEvaluation, tenant: oid, authorize?: false)
      assert length(evals) == 1
      assert hd(evals).status == :below

      triggers = Ash.read!(InterventionTrigger, tenant: oid, authorize?: false)
      assert length(triggers) == 1

      trigger = hd(triggers)
      assert trigger.trigger_type == :goal_at_risk
      assert trigger.severity == :high
      assert trigger.status == :active
    end

    test "trigger is resolved when re-import pushes school above goal after being below" do
      oid = gen_oid()
      {school, year} = create_base(oid)

      students =
        Enum.map(1..6, fn i ->
          s = create_student(oid, "S#{i}")
          enroll_student(oid, s, school, year)
          s
        end)

      _goal = create_fall_sgp_goal(oid, school, 50)

      # First import: low SGPs → :below → trigger created
      low_rows = Enum.map(students, fn s -> nwea_row(s.uic, 200, 25) end)
      assert :ok = run_csv_import(oid, school, year, low_rows)
      assert :ok = run_snapshot_worker(oid, school, year)
      assert :ok = run_goal_worker(oid, school, year)

      triggers_after_first = Ash.read!(InterventionTrigger, tenant: oid, authorize?: false)
      assert length(triggers_after_first) == 1
      assert hd(triggers_after_first).status == :active

      # Re-import: high SGPs → :meets → trigger resolved
      high_rows = Enum.map(students, fn s -> nwea_row(s.uic, 225, 65) end)
      assert :ok = run_csv_import(oid, school, year, high_rows)
      assert :ok = run_snapshot_worker(oid, school, year)
      assert :ok = run_goal_worker(oid, school, year)

      all_triggers = Ash.read!(InterventionTrigger, tenant: oid, authorize?: false)
      resolved = Enum.filter(all_triggers, &(&1.status == :resolved))
      active = Enum.filter(all_triggers, &(&1.status == :active))

      assert length(resolved) == 1
      assert active == []
    end
  end
end
