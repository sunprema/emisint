defmodule Emisint.Workers.MdeImportWorker do
  @moduledoc """
  Oban worker that runs `MdeImporter.import_file/1` in the background.

  This job imports MDE public state assessment data from a local CSV file
  into the normalized dimension + fact tables. Because MDE data is not
  tenant-scoped, no `organization_id` is required in the job args.

  ## Enqueuing

      %{file_path: "/path/to/mde_assessment_results.csv"}
      |> Emisint.Workers.MdeImportWorker.new()
      |> Oban.insert!()

  ## Job args

    - `file_path` — absolute path to the MDE CSV file on the server

  """

  use Oban.Worker, queue: :data_ingestion, max_attempts: 2

  alias Emisint.Assessments.MdeImporter

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"file_path" => file_path}}) do
    case MdeImporter.import_file(file_path) do
      {:ok, stats} ->
        log_success(file_path, stats)
        :ok

      {:error, reason} ->
        log_failure(file_path, reason)
        {:error, reason}
    end
  end

  defp log_success(path, stats) do
    require Logger

    Logger.info(
      "[MdeImportWorker] Completed import of #{Path.basename(path)} — " <>
        "ISDs: #{stats.isds}, Districts: #{stats.districts}, " <>
        "Buildings: #{stats.buildings}, Results: #{stats.results}, " <>
        "Errors: #{stats.errors}"
    )
  end

  defp log_failure(path, reason) do
    require Logger
    Logger.error("[MdeImportWorker] Failed to import #{Path.basename(path)}: #{reason}")
  end
end
