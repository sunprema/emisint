defmodule Emisint.Workers.CsvImportWorkerTest do
  use Emisint.DataCase, async: false
  use Oban.Testing, repo: Emisint.Repo

  alias Emisint.Accounts.School
  alias Emisint.Analytics.DataSyncLog
  alias Emisint.Assessments.AssessmentResult
  alias Emisint.Registry.{AcademicYear, Student}
  alias Emisint.Workers.CsvImportWorker

  defp org_id, do: Ash.UUID.generate()

  defp setup_org(oid) do
    school =
      Ash.create!(School,
        %{name: "CSV Import Academy", mde_district_code: "25010", mde_building_code: "08001"},
        tenant: oid,
        authorize?: false
      )

    year =
      Ash.create!(AcademicYear,
        %{label: "2024-2025", start_date: ~D[2024-09-03], end_date: ~D[2025-06-13]},
        tenant: oid,
        authorize?: false
      )

    student =
      Ash.create!(Student,
        %{uic: "M123456", first_name: "Alice", last_name: "Smith"},
        tenant: oid,
        authorize?: false
      )

    {school, year, student}
  end

  defp nwea_row(uic) do
    %{
      "StudentID" => uic,
      "Subject" => "Mathematics",
      "TermName" => "Fall 2024",
      "TestRITScore" => "218.5",
      "TestPercentile" => "62",
      "ConditionalSGP" => "55",
      "TestDate" => "2024-10-15"
    }
  end

  defp i_ready_row(uic) do
    %{
      "Student_ID" => uic,
      "Subject" => "Reading",
      "Period" => "Fall",
      "Scale_Score" => "502",
      "Percentile" => "48",
      "Overall_Placement" => "3",
      "Completion_Date" => "2024-10-20"
    }
  end

  defp run_worker(oid, school, year, provider, rows) do
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

  describe "NWEA MAP import" do
    test "creates AssessmentResults for known UICs" do
      oid = org_id()
      {school, year, student} = setup_org(oid)

      assert :ok = run_worker(oid, school, year, "nwea_map", [nwea_row(student.uic)])

      results = Ash.read!(AssessmentResult, tenant: oid, authorize?: false)
      assert length(results) == 1

      result = hd(results)
      assert result.assessment_type == :nwea_map
      assert result.subject == "math"
      assert result.testing_window == :fall
      assert result.sgp == 55
    end

    test "ignores rows with unknown UICs" do
      oid = org_id()
      {school, year, _student} = setup_org(oid)

      assert :ok = run_worker(oid, school, year, "nwea_map", [nwea_row("UNKNOWN999")])

      results = Ash.read!(AssessmentResult, tenant: oid, authorize?: false)
      assert results == []
    end

    test "creates a completed DataSyncLog" do
      oid = org_id()
      {school, year, student} = setup_org(oid)

      assert :ok = run_worker(oid, school, year, "nwea_map", [nwea_row(student.uic)])

      logs = Ash.read!(DataSyncLog, tenant: oid, authorize?: false)
      assert length(logs) == 1
      log = hd(logs)
      assert log.status == :completed
      assert log.records_processed == 1
      assert log.records_failed == 0
    end

    test "enqueues SnapshotRefreshWorker after successful import" do
      oid = org_id()
      {school, year, student} = setup_org(oid)

      assert :ok = run_worker(oid, school, year, "nwea_map", [nwea_row(student.uic)])

      assert_enqueued(
        worker: Emisint.Workers.SnapshotRefreshWorker,
        args: %{
          "organization_id" => oid,
          "school_id" => school.id,
          "academic_year_id" => year.id
        }
      )
    end
  end

  describe "i-Ready import" do
    test "creates AssessmentResults for known UICs" do
      oid = org_id()
      {school, year, student} = setup_org(oid)

      assert :ok = run_worker(oid, school, year, "i_ready", [i_ready_row(student.uic)])

      results = Ash.read!(AssessmentResult, tenant: oid, authorize?: false)
      assert length(results) == 1

      result = hd(results)
      assert result.assessment_type == :i_ready
      assert result.subject == "reading"
      assert result.testing_window == :fall
      assert result.proficiency_level == "3"
    end
  end

  describe "upsert behaviour" do
    test "re-importing the same row updates the record, not duplicates it" do
      oid = org_id()
      {school, year, student} = setup_org(oid)

      rows = [nwea_row(student.uic)]
      assert :ok = run_worker(oid, school, year, "nwea_map", rows)
      assert :ok = run_worker(oid, school, year, "nwea_map", rows)

      results = Ash.read!(AssessmentResult, tenant: oid, authorize?: false)
      assert length(results) == 1
    end
  end
end
