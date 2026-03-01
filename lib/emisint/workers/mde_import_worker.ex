defmodule Emisint.Workers.MdeImportWorker do
  @moduledoc """
  Oban worker that runs `MdeImporter.import_file/1` in the background.

  This job imports MDE public state assessment data from a local CSV file
  into the normalized dimension + fact tables. Because MDE data is not
  tenant-scoped, no `organization_id` is required in the job args.

  On completion (success or failure) it:
    1. Broadcasts the result on the `"mde_import"` PubSub topic so any
       subscribed LiveView can update without polling.
    2. Deletes the temporary upload file from disk.

  ## Enqueuing

      %{file_path: "/tmp/mde_import_12345.csv"}
      |> Emisint.Workers.MdeImportWorker.new()
      |> Oban.insert!()

  ## Job args

    - `file_path` — absolute path to the MDE CSV file on the server

  """

  use Oban.Worker, queue: :data_ingestion, max_attempts: 2

  require Logger

  alias Emisint.Assessments.MdeImporter
  alias Emisint.Workers.MdeComparisonSnapshotWorker

  @pubsub_topic "mde_import"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"file_path" => file_path}}) do
    result = MdeImporter.import_file(file_path)

    case result do
      {:ok, stats} ->
        Logger.info(
          "[MdeImportWorker] Completed #{Path.basename(file_path)} — " <>
            "ISDs: #{stats.isds}, Districts: #{stats.districts}, " <>
            "Buildings: #{stats.buildings}, Results: #{stats.results}, " <>
            "Errors: #{stats.errors}"
        )

        Phoenix.PubSub.broadcast(
          Emisint.PubSub,
          @pubsub_topic,
          {:mde_import_completed, stats}
        )

        if stats.school_year do
          %{"school_year" => stats.school_year}
          |> MdeComparisonSnapshotWorker.new()
          |> Oban.insert!()
        end

        :ok

      {:error, reason} ->
        Logger.error("[MdeImportWorker] Failed #{Path.basename(file_path)}: #{reason}")

        Phoenix.PubSub.broadcast(
          Emisint.PubSub,
          @pubsub_topic,
          {:mde_import_failed, reason}
        )

        {:error, reason}
    end
  after
    # Always clean up the temp file regardless of outcome
    File.rm(file_path)
  end
end
