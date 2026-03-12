defmodule Emisint.Workers.EntityMasterImportWorker do
  @moduledoc """
  Oban worker that runs `MdeEntityMasterImporter.import_file/1` in the background.

  Imports the MDE EntityMaster daily CSV into the shared `mde_entity_masters`
  reference table. No tenant scope is required.

  On completion (success or failure) it:
    1. Broadcasts the result on the `"entity_master_import"` PubSub topic so
       any subscribed LiveView can update without polling.
    2. Deletes the temporary upload file from disk.

  ## Enqueuing

      %{file_path: "/tmp/entity_master_12345.csv"}
      |> Emisint.Workers.EntityMasterImportWorker.new()
      |> Oban.insert!()

  ## Job args

    - `file_path` — absolute path to the EntityMaster CSV file on the server

  """

  use Oban.Worker, queue: :data_ingestion, max_attempts: 2

  require Logger

  alias Emisint.Assessments.MdeEntityMasterImporter

  @pubsub_topic "entity_master_import"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bucket" => _bucket, "key" => key}}) do
    tmp_path =
      Path.join(System.tmp_dir!(), "entity_master_#{System.unique_integer([:positive])}.csv")

    try do
      Emisint.Storage.download_to_file!(key, tmp_path)
      result = MdeEntityMasterImporter.import_file(tmp_path)

      case result do
        {:ok, stats} ->
          Logger.info(
            "[EntityMasterImportWorker] Completed #{Path.basename(key)} — " <>
              "Records: #{stats.records}, Errors: #{stats.errors}"
          )

          Phoenix.PubSub.broadcast(
            Emisint.PubSub,
            @pubsub_topic,
            {:entity_master_import_completed, stats}
          )

          :ok

        {:error, reason} ->
          Logger.error(
            "[EntityMasterImportWorker] Failed #{Path.basename(key)}: #{reason}"
          )

          Phoenix.PubSub.broadcast(
            Emisint.PubSub,
            @pubsub_topic,
            {:entity_master_import_failed, reason}
          )

          {:error, reason}
      end
    after
      File.rm(tmp_path)
      Emisint.Storage.delete(key)
    end
  end
end
