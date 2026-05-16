defmodule Emisint.Workers.MdeEmoContactImportWorker do
  @moduledoc """
  Oban worker that imports the MDE Open/Active EMO contact list CSV in the background.

  ## Job args

    - `bucket` — Tigris bucket name
    - `key`    — S3 object key for the uploaded CSV
    - `log_id` — (optional) UUID of the MdeImportLog record to update

  """

  use Oban.Worker, queue: :data_ingestion, max_attempts: 2

  require Logger

  alias Emisint.Assessments.MdeEmoContactImporter
  alias Emisint.Assessments.MdeImportLog

  @pubsub_topic "emo_contact_import"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bucket" => _bucket, "key" => key} = args}) do
    tmp_path =
      Path.join(System.tmp_dir!(), "emo_contact_#{System.unique_integer([:positive])}.csv")

    log_id = Map.get(args, "log_id")

    try do
      Emisint.Storage.download_to_file!(key, tmp_path)
      result = MdeEmoContactImporter.import_file(tmp_path)

      case result do
        {:ok, stats} ->
          Logger.info(
            "[MdeEmoContactImportWorker] Completed #{Path.basename(key)} — " <>
              "Records: #{stats.records}, Errors: #{stats.errors}"
          )

          update_log(log_id, :completed, %{
            records_processed: stats.records,
            error_count: stats.errors
          })

          Phoenix.PubSub.broadcast(
            Emisint.PubSub,
            @pubsub_topic,
            {:emo_contact_import_completed, stats}
          )

          :ok

        {:error, reason} ->
          Logger.error(
            "[MdeEmoContactImportWorker] Failed #{Path.basename(key)}: #{reason}"
          )

          update_log(log_id, :failed, %{error_message: to_string(reason)})

          Phoenix.PubSub.broadcast(
            Emisint.PubSub,
            @pubsub_topic,
            {:emo_contact_import_failed, reason}
          )

          {:error, reason}
      end
    after
      File.rm(tmp_path)
      Emisint.Storage.delete(key)
    end
  end

  defp update_log(nil, _status, _attrs), do: :ok

  defp update_log(log_id, :completed, attrs) do
    case Ash.get(MdeImportLog, log_id, authorize?: false) do
      {:ok, log} -> Ash.update(log, attrs, action: :mark_completed, authorize?: false)
      _ -> :ok
    end
  end

  defp update_log(log_id, :failed, attrs) do
    case Ash.get(MdeImportLog, log_id, authorize?: false) do
      {:ok, log} -> Ash.update(log, attrs, action: :mark_failed, authorize?: false)
      _ -> :ok
    end
  end
end
