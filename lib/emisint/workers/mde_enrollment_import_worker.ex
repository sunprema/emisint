defmodule Emisint.Workers.MdeEnrollmentImportWorker do
  @moduledoc """
  Oban worker that runs `MdeEnrollmentImporter.import_file/1` in the background.

  Imports MDE annual student enrollment counts (building/district/ISD rollups)
  from a local CSV file into `mde_enrollment_results`. Because MDE enrollment
  data is not tenant-scoped, no `organization_id` is required in the job args.

  On completion (success or failure) it:
    1. Broadcasts the result on the `"enrollment_import"` PubSub topic so any
       subscribed LiveView can update without polling.
    2. Deletes the temporary upload file from disk.

  ## Enqueuing

      %{file_path: "/tmp/enrollment_import_12345.csv"}
      |> Emisint.Workers.MdeEnrollmentImportWorker.new()
      |> Oban.insert!()

  ## Job args

    - `file_path` — absolute path to the enrollment CSV file on the server

  """

  use Oban.Worker, queue: :data_ingestion, max_attempts: 2

  require Logger

  alias Emisint.Assessments.MdeEnrollmentImporter

  @pubsub_topic "enrollment_import"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"file_path" => file_path}}) do
    result = MdeEnrollmentImporter.import_file(file_path)

    case result do
      {:ok, stats} ->
        Logger.info(
          "[MdeEnrollmentImportWorker] Completed #{Path.basename(file_path)} — " <>
            "Records: #{stats.records}, Errors: #{stats.errors}"
        )

        Phoenix.PubSub.broadcast(
          Emisint.PubSub,
          @pubsub_topic,
          {:enrollment_import_completed, stats}
        )

        :ok

      {:error, reason} ->
        Logger.error(
          "[MdeEnrollmentImportWorker] Failed #{Path.basename(file_path)}: #{reason}"
        )

        Phoenix.PubSub.broadcast(
          Emisint.PubSub,
          @pubsub_topic,
          {:enrollment_import_failed, reason}
        )

        {:error, reason}
    end
  after
    # Always clean up the temp file regardless of outcome
    File.rm(file_path)
  end
end
