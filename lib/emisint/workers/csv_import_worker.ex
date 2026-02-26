defmodule Emisint.Workers.CsvImportWorker do
  @moduledoc """
  Oban worker that imports assessment data from a CSV export (NWEA MAP, i-Ready, etc.).

  Expected job args:
    - `organization_id`   — tenant UUID
    - `school_id`         — UUID of the target school
    - `academic_year_id`  — UUID of the target academic year
    - `provider_code`     — "nwea_map" | "i_ready"
    - `rows`              — list of string-keyed maps (pre-parsed CSV rows)

  Pipeline:
    1. Create DataSyncLog entry (pending → running)
    2. Map each row to AssessmentResult attrs using provider column mapping
    3. Resolve student UICs → student_id UUIDs
    4. Bulk-upsert AssessmentResults
    5. Update DataSyncLog with outcome (completed / failed)
    6. Enqueue SnapshotRefreshWorker
  """

  use Oban.Worker, queue: :data_ingestion, max_attempts: 3

  alias Emisint.Analytics.DataSyncLog
  alias Emisint.Assessments.AssessmentResult
  alias Emisint.Registry.Student

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "organization_id" => org_id,
          "school_id" => school_id,
          "academic_year_id" => academic_year_id,
          "provider_code" => provider_code,
          "rows" => rows
        }
      }) do
    # 1. Create DataSyncLog
    {:ok, log} =
      Ash.create(DataSyncLog,
        %{
          job_type: :csv_import,
          metadata: %{provider_code: provider_code, school_id: school_id, row_count: length(rows)}
        },
        tenant: org_id,
        authorize?: false
      )

    Ash.update!(log, %{started_at: DateTime.utc_now()}, action: :start, tenant: org_id, authorize?: false)

    try do
      # 2. Map CSV rows to candidate attrs (keyed by UIC, not student_id yet)
      mapped = map_rows(provider_code, rows, academic_year_id)

      # 3. Resolve UICs → student_ids
      uics = mapped |> Enum.map(& &1.uic) |> Enum.uniq()
      uic_set = MapSet.new(uics)

      uic_to_id =
        Student
        |> Ash.read!(tenant: org_id, authorize?: false)
        |> Enum.filter(fn s -> MapSet.member?(uic_set, s.uic) end)
        |> Map.new(fn s -> {s.uic, s.id} end)

      attrs_list =
        mapped
        |> Enum.filter(fn row -> Map.has_key?(uic_to_id, row.uic) end)
        |> Enum.map(fn row ->
          row
          |> Map.put(:student_id, uic_to_id[row.uic])
          |> Map.delete(:uic)
        end)

      # 4. Bulk upsert
      result =
        Ash.bulk_create(attrs_list, AssessmentResult, :bulk_upsert,
          tenant: org_id,
          authorize?: false,
          return_errors?: true,
          upsert_fields: [:raw_score, :scale_score, :proficiency_level, :sgp, :growth_target, :percentile, :test_date, :source]
        )

      processed = length(attrs_list) - result.error_count
      failed = result.error_count

      # 5. Update DataSyncLog
      Ash.update!(log,
        %{records_processed: processed, records_failed: failed, completed_at: DateTime.utc_now()},
        action: :complete,
        tenant: org_id,
        authorize?: false
      )

      # 6. Enqueue SnapshotRefreshWorker
      %{
        organization_id: org_id,
        school_id: school_id,
        academic_year_id: academic_year_id
      }
      |> Emisint.Workers.SnapshotRefreshWorker.new()
      |> Oban.insert!()

      :ok
    rescue
      error ->
        Ash.update!(log,
          %{error_message: Exception.message(error), completed_at: DateTime.utc_now()},
          action: :fail,
          tenant: org_id,
          authorize?: false
        )

        reraise error, __STACKTRACE__
    end
  end

  # ---------------------------------------------------------------------------
  # Column mappers per provider
  # ---------------------------------------------------------------------------

  defp map_rows("nwea_map", rows, academic_year_id) do
    Enum.map(rows, fn row ->
      %{
        uic: row["StudentID"],
        assessment_type: :nwea_map,
        subject: map_nwea_subject(row["Subject"]),
        testing_window: map_testing_window(row["TermName"]),
        scale_score: parse_decimal(row["TestRITScore"]),
        percentile: parse_integer(row["TestPercentile"]),
        sgp: parse_integer(row["ConditionalSGP"]),
        test_date: parse_date(row["TestDate"]),
        source: "NWEA MAP CSV",
        academic_year_id: academic_year_id
      }
    end)
  end

  defp map_rows("i_ready", rows, academic_year_id) do
    Enum.map(rows, fn row ->
      %{
        uic: row["Student_ID"],
        assessment_type: :i_ready,
        subject: String.downcase(row["Subject"] || ""),
        testing_window: map_testing_window(row["Period"]),
        scale_score: parse_decimal(row["Scale_Score"]),
        percentile: parse_integer(row["Percentile"]),
        proficiency_level: row["Overall_Placement"],
        test_date: parse_date(row["Completion_Date"]),
        source: "i-Ready CSV",
        academic_year_id: academic_year_id
      }
    end)
  end

  defp map_nwea_subject("Mathematics"), do: "math"
  defp map_nwea_subject("Reading"), do: "reading"
  defp map_nwea_subject("Language Usage"), do: "language"
  defp map_nwea_subject("Science - General Science"), do: "science"
  defp map_nwea_subject(other), do: String.downcase(other || "unknown")

  defp map_testing_window(term) when is_binary(term) do
    cond do
      String.contains?(String.downcase(term), "fall") -> :fall
      String.contains?(String.downcase(term), "winter") -> :winter
      String.contains?(String.downcase(term), "spring") -> :spring
      true -> :spring
    end
  end

  defp map_testing_window(_), do: :spring

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(val) when is_binary(val) do
    case Decimal.parse(val) do
      {d, _} -> d
      :error -> nil
    end
  end

  defp parse_decimal(val), do: Decimal.new(val)

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil

  defp parse_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp parse_integer(val) when is_integer(val), do: val

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(val) when is_binary(val) do
    case Date.from_iso8601(val) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
