defmodule Emisint.Workers.MdeSssImportWorker do
  @moduledoc """
  Oban worker that imports the SSS peer-group file in the background.

  ## Job args

    - `bucket` — object storage bucket name
    - `key`    — object storage key for the uploaded file
    - `log_id` — (optional) UUID of the MdeImportLog record to update

  """

  use Oban.Worker, queue: :data_ingestion, max_attempts: 2

  require Logger

  alias Emisint.Assessments.MdeImportLog
  alias Emisint.Assessments.MdeSssImporter

  @pubsub_topic "sss_import"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bucket" => _bucket, "key" => key} = args}) do
    ext = Path.extname(key)
    tmp_path = Path.join(System.tmp_dir!(), "sss_#{System.unique_integer([:positive])}#{ext}")
    basename = Path.basename(key)
    log_id = Map.get(args, "log_id")

    try do
      Logger.info("[MdeSssImportWorker] Downloading #{basename}…")
      Emisint.Storage.download_to_file!(key, tmp_path)

      result = MdeSssImporter.import_file(tmp_path)

      case result do
        {:ok, stats} ->
          Logger.info(
            "[MdeSssImportWorker] Completed #{basename} — " <>
              "Rows: #{stats.total_rows}, Members: #{stats.records}, " <>
              "Groups: #{stats.groups}, Schools: #{stats.schools}, " <>
              "Warnings: #{stats.warnings}, Errors: #{stats.errors}"
          )

          update_log(log_id, :completed, %{
            records_processed: stats.records,
            error_count: stats.errors,
            metadata: %{
              total_rows: stats.total_rows,
              groups: stats.groups,
              schools: stats.schools,
              warnings: stats.warnings
            }
          })

          Phoenix.PubSub.broadcast(
            Emisint.PubSub,
            @pubsub_topic,
            {:sss_import_completed, stats}
          )

          :ok

        {:error, reason} ->
          Logger.error("[MdeSssImportWorker] Failed #{basename}: #{reason}")
          update_log(log_id, :failed, %{error_message: to_string(reason)})

          Phoenix.PubSub.broadcast(
            Emisint.PubSub,
            @pubsub_topic,
            {:sss_import_failed, reason}
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
