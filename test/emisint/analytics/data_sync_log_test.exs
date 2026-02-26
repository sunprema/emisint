defmodule Emisint.Analytics.DataSyncLogTest do
  use Emisint.DataCase, async: true

  alias Emisint.Analytics.DataSyncLog

  defp org_id, do: Ash.UUID.generate()

  defp create_log(oid, attrs \\ %{}) do
    Ash.create!(DataSyncLog,
      Map.merge(%{job_type: :csv_import}, attrs),
      tenant: oid,
      authorize?: false
    )
  end

  describe "create" do
    test "creates a log with pending status" do
      oid = org_id()
      log = create_log(oid)
      assert log.status == :pending
      assert log.job_type == :csv_import
    end

    test "supports all job_type values" do
      oid = org_id()

      for type <- [:csv_import, :snapshot_refresh, :goal_recalculation, :mde_sync] do
        log = create_log(oid, %{job_type: type})
        assert log.job_type == type
      end
    end

    test "stores optional metadata" do
      oid = org_id()
      # Map is serialized to JSON and back — atom keys become string keys
      log = create_log(oid, %{metadata: %{provider: "nwea", rows: 200}})
      assert log.metadata["provider"] == "nwea"
      assert log.metadata["rows"] == 200
    end
  end

  describe ":start action" do
    test "transitions status to running" do
      oid = org_id()
      log = create_log(oid)
      updated = Ash.update!(log, %{started_at: DateTime.utc_now()}, action: :start, tenant: oid, authorize?: false)
      assert updated.status == :running
      assert updated.started_at != nil
    end
  end

  describe ":complete action" do
    test "transitions status to completed with counts" do
      oid = org_id()
      log = create_log(oid)
      Ash.update!(log, %{started_at: DateTime.utc_now()}, action: :start, tenant: oid, authorize?: false)
      |> Ash.update!(%{records_processed: 95, records_failed: 5, completed_at: DateTime.utc_now()},
        action: :complete, tenant: oid, authorize?: false)
      |> then(fn updated ->
        assert updated.status == :completed
        assert updated.records_processed == 95
        assert updated.records_failed == 5
        assert updated.completed_at != nil
      end)
    end
  end

  describe ":fail action" do
    test "transitions status to failed with error message" do
      oid = org_id()
      log = create_log(oid)

      failed =
        Ash.update!(log,
          %{error_message: "CSV parse error at row 3", completed_at: DateTime.utc_now()},
          action: :fail,
          tenant: oid,
          authorize?: false
        )

      assert failed.status == :failed
      assert failed.error_message == "CSV parse error at row 3"
    end
  end

  describe "multitenancy" do
    test "logs are isolated per org" do
      oid_a = org_id()
      oid_b = org_id()
      create_log(oid_a)
      create_log(oid_b)

      logs_a = Ash.read!(DataSyncLog, tenant: oid_a, authorize?: false)
      logs_b = Ash.read!(DataSyncLog, tenant: oid_b, authorize?: false)

      assert length(logs_a) == 1
      assert length(logs_b) == 1
      assert hd(logs_a).organization_id == oid_a
      assert hd(logs_b).organization_id == oid_b
    end
  end
end
