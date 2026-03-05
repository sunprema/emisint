defmodule Emisint.Workers.MdeSatImportWorker do
  @moduledoc """
  Oban worker that runs `MdeSatImporter.import_file/1` in the background.

  Imports MDE SAT college-readiness aggregate data (building/district/ISD rollups
  broken out by subgroup) into `mde_sat_results`. The data is not tenant-scoped, so
  no `organization_id` is required in the job args.

  On completion (success or failure) it:
    1. Broadcasts the result on the `"sat_import"` PubSub topic so any
       subscribed LiveView can update without polling.
    2. Deletes the temporary upload file from disk.

  ## Enqueuing

      %{"file_path" => "/tmp/sat_import_12345.csv"}
      |> Emisint.Workers.MdeSatImportWorker.new()
      |> Oban.insert!()

  ## Job args

    - `file_path` — absolute path to the SAT CSV file on the server

  """

  use Oban.Worker, queue: :data_ingestion, max_attempts: 2

  require Logger

  alias Emisint.Assessments.MdeSatImporter

  @pubsub_topic "sat_import"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"file_path" => file_path}}) do
    result = MdeSatImporter.import_file(file_path)

    case result do
      {:ok, stats} ->
        Logger.info(
          "[MdeSatImportWorker] Completed #{Path.basename(file_path)} — " <>
            "Records: #{stats.records}, Errors: #{stats.errors}"
        )

        Phoenix.PubSub.broadcast(
          Emisint.PubSub,
          @pubsub_topic,
          {:sat_import_completed, stats}
        )

        :ok

      {:error, reason} ->
        Logger.error(
          "[MdeSatImportWorker] Failed #{Path.basename(file_path)}: #{reason}"
        )

        Phoenix.PubSub.broadcast(
          Emisint.PubSub,
          @pubsub_topic,
          {:sat_import_failed, reason}
        )

        {:error, reason}
    end
  after
    # Always clean up the temp file regardless of outcome
    File.rm(file_path)
  end
end
