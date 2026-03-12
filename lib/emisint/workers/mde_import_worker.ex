defmodule Emisint.Workers.MdeImportWorker do
  @moduledoc """
  Oban worker that runs `MdeImporter.import_file/1` in the background.

  Accepts optional `log_id` in job args — when present, updates the
  `MdeImportLog` record with final status and stats on completion.

  ## Job args

    - `bucket` — Tigris bucket name
    - `key`    — S3 object key for the uploaded CSV
    - `log_id` — (optional) UUID of the MdeImportLog record to update

  """

  use Oban.Worker, queue: :data_ingestion, max_attempts: 2

  require Logger

  alias Emisint.Assessments.MdeImporter
  alias Emisint.Assessments.MdeImportLog
  alias Emisint.Workers.MdeComparisonSnapshotWorker

  @pubsub_topic "mde_import"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bucket" => _bucket, "key" => key} = args}) do
    tmp_path = Path.join(System.tmp_dir!(), "mde_#{System.unique_integer([:positive])}.csv")
    basename = Path.basename(key)
    log_id = Map.get(args, "log_id")

    try do
      Logger.info("[MdeImportWorker] Downloading #{basename} from Tigris…")
      dl_start = System.monotonic_time(:millisecond)
      Emisint.Storage.download_to_file!(key, tmp_path)
      dl_ms = System.monotonic_time(:millisecond) - dl_start
      %{size: size} = File.stat!(tmp_path)
      Logger.info("[MdeImportWorker] Download complete — #{format_bytes(size)} in #{dl_ms}ms")

      Logger.info("[MdeImportWorker] Starting import of #{basename}…")
      import_start = System.monotonic_time(:millisecond)
      result = MdeImporter.import_file(tmp_path)

      case result do
        {:ok, stats} ->
          import_ms = System.monotonic_time(:millisecond) - import_start

          Logger.info(
            "[MdeImportWorker] Completed #{basename} in #{import_ms}ms — " <>
              "ISDs: #{stats.isds}, Districts: #{stats.districts}, " <>
              "Buildings: #{stats.buildings}, Results: #{stats.results}, " <>
              "Errors: #{stats.errors}"
          )

          update_log(log_id, :completed, %{
            records_processed: stats.results,
            error_count: stats.errors,
            school_year: stats.school_year,
            metadata: %{
              isds: stats.isds,
              districts: stats.districts,
              buildings: stats.buildings,
              duration_ms: import_ms
            }
          })

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
          Logger.error("[MdeImportWorker] Failed #{basename}: #{reason}")

          update_log(log_id, :failed, %{error_message: to_string(reason)})

          Phoenix.PubSub.broadcast(
            Emisint.PubSub,
            @pubsub_topic,
            {:mde_import_failed, reason}
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

  defp format_bytes(bytes) when bytes >= 1_048_576,
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_bytes(bytes) when bytes >= 1024,
    do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes), do: "#{bytes} B"
end
