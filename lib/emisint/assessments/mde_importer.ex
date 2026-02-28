defmodule Emisint.Assessments.MdeImporter do
  @batch_size 500

  @moduledoc """
  Imports MDE public state assessment CSV data into the normalized relational tables.

  The CSV must follow the standard MDE aggregate export format with a header row.
  File may be very large (millions of rows); the importer uses two streaming passes
  so the fact rows are never fully loaded into memory.

  ## Pipeline

    1. **First pass** — stream the file to collect unique ISDs, districts, and buildings
       (these are tiny sets: ~57 ISDs, ~900 districts, ~4 000 buildings statewide).
       Rows with `building_code = "0"` or `district_code = "0"` are sentinel rollup rows
       and are skipped when collecting dimensions (no phantom "0" entities are created).
    2. **Upsert dimension tables** in FK order:
       `MdeIsd → MdeDistrict → MdeBuilding`
       After each upsert, read back the table to build a `code → UUID` lookup map.
    3. **Second pass** — stream fact rows in batches of #{@batch_size}, tag each row as
       `:building`, `:district`, or `:isd` granularity, resolve UUIDs, and bulk-upsert
       `MdeStateAssessmentResult` via the appropriate action for each granularity.

  ## Usage

      iex> Emisint.Assessments.MdeImporter.import_file("priv/data/mde_assessment_results.csv")
      {:ok, %{isds: 57, districts: 842, buildings: 3891, results: 1_200_000, errors: 0}}

  """

  alias Emisint.Assessments.{MdeBuilding, MdeDistrict, MdeIsd, MdeStateAssessmentResult}

  # Score fields updated on conflict (same for all three upsert actions)
  @score_upsert_fields [
    :total_advanced,
    :total_proficient,
    :total_partially_proficient,
    :total_not_proficient,
    :total_surpassed,
    :total_attained,
    :total_emerging_towards,
    :total_met,
    :total_did_not_meet,
    :number_assessed,
    :percent_advanced,
    :percent_proficient,
    :percent_partially_proficient,
    :percent_not_proficient,
    :percent_surpassed,
    :percent_attained,
    :percent_emerging_towards,
    :percent_met,
    :percent_did_not_meet,
    :avg_ss,
    :std_dev_ss,
    :mean_pts_earned,
    :min_scale_score,
    :max_scale_score,
    :scale_score_25,
    :scale_score_50,
    :scale_score_75
  ]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec import_file(Path.t()) :: {:ok, map()} | {:error, String.t()}
  def import_file(path) do
    with :ok <- validate_file(path) do
      # First pass — cheap: only keeps unique dimension rows in memory.
      # Skips "0" sentinel codes so no phantom records are created.
      {isds, districts, buildings} = collect_dimensions(path)

      # Upsert ISDs, then build isd_code → UUID map
      upsert_isds(isds)
      isd_map = build_code_map(MdeIsd, :isd_code)

      # Upsert districts (needs ISD UUIDs), then build district_code → UUID map
      upsert_districts(districts, isd_map)
      district_map = build_code_map(MdeDistrict, :district_code)

      # Upsert buildings (needs district UUIDs), then build building_code → UUID map
      upsert_buildings(buildings, district_map)
      building_map = build_code_map(MdeBuilding, :building_code)

      # Second pass — streamed in batches, never fully in memory.
      # Routes rows to the correct upsert action by rollup granularity.
      {result_count, error_count} = upsert_results(path, building_map, district_map, isd_map)

      {:ok,
       %{
         isds: map_size(isds),
         districts: map_size(districts),
         buildings: map_size(buildings),
         results: result_count,
         errors: error_count
       }}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  # ---------------------------------------------------------------------------
  # Streaming helpers
  # ---------------------------------------------------------------------------

  # Streams the CSV as string-keyed maps, one per data row.
  # Uses Stream.transform to capture the header row and zip it with each data row.
  # Handles optional UTF-8 BOM produced by some Windows CSV exports.
  defp stream_as_maps(path) do
    File.stream!(path)
    |> NimbleCSV.RFC4180.parse_stream(skip_headers: false)
    |> Stream.transform(nil, fn
      # First row: capture headers, strip BOM if present, emit nothing
      [first | rest], nil ->
        headers = [String.trim_leading(first, "\uFEFF") | rest]
        {[], headers}

      # Subsequent rows: zip with headers to produce a string-keyed map
      row, headers ->
        row_map = headers |> Enum.zip(row) |> Map.new()
        {[row_map], headers}
    end)
  end

  # ---------------------------------------------------------------------------
  # First pass — collect unique dimension records
  # ---------------------------------------------------------------------------

  defp collect_dimensions(path) do
    stream_as_maps(path)
    |> Enum.reduce({%{}, %{}, %{}}, fn row, {isds, districts, buildings} ->
      isd_code = row["ISDCode"]
      district_code = row["DistrictCode"]
      building_code = row["BuildingCode"]

      # ISDs are always real — isd_code is never "0"
      isds =
        Map.put_new(isds, isd_code, %{
          isd_code: isd_code,
          isd_name: row["ISDName"]
        })

      # district_code == "0" means ISD-level rollup — skip, no real district
      districts =
        if district_code == "0" do
          districts
        else
          Map.put_new(districts, district_code, %{
            district_code: district_code,
            district_name: row["DistrictName"],
            county_code: nilify(row["CountyCode"]),
            county_name: nilify(row["CountyName"]),
            entity_type: nilify(row["EntityType"]),
            # Kept as code here; resolved to UUID before upsert
            isd_code: isd_code
          })
        end

      # building_code == "0" means district-level rollup — skip, no real building
      buildings =
        if building_code == "0" do
          buildings
        else
          Map.put_new(buildings, building_code, %{
            building_code: building_code,
            building_name: row["BuildingName"],
            school_level: nilify(row["SchoolLevel"]),
            locale: nilify(row["Locale"]),
            mistem_name: nilify(row["MISTEM_NAME"]),
            mistem_code: nilify(row["MISTEM_CODE"]),
            # Kept as code here; resolved to UUID before upsert
            district_code: district_code
          })
        end

      {isds, districts, buildings}
    end)
  end

  # ---------------------------------------------------------------------------
  # Dimension upserts
  # ---------------------------------------------------------------------------

  defp upsert_isds(isds_map) do
    isds_map
    |> Map.values()
    |> Ash.bulk_create(MdeIsd, :upsert,
      authorize?: false,
      return_errors?: true,
      upsert_fields: [:isd_name]
    )
  end

  defp upsert_districts(districts_map, isd_map) do
    districts_map
    |> Map.values()
    |> Enum.map(fn d ->
      d
      |> Map.put(:mde_isd_id, Map.get(isd_map, d.isd_code))
      |> Map.delete(:isd_code)
    end)
    |> Ash.bulk_create(MdeDistrict, :upsert,
      authorize?: false,
      return_errors?: true,
      upsert_fields: [:district_name, :county_code, :county_name, :entity_type, :mde_isd_id]
    )
  end

  defp upsert_buildings(buildings_map, district_map) do
    buildings_map
    |> Map.values()
    |> Enum.map(fn b ->
      b
      |> Map.put(:mde_district_id, Map.get(district_map, b.district_code))
      |> Map.delete(:district_code)
    end)
    |> Ash.bulk_create(MdeBuilding, :upsert,
      authorize?: false,
      return_errors?: true,
      upsert_fields: [
        :building_name,
        :school_level,
        :locale,
        :mistem_name,
        :mistem_code,
        :mde_district_id
      ]
    )
  end

  # ---------------------------------------------------------------------------
  # Second pass — stream fact rows in batches
  # ---------------------------------------------------------------------------

  defp upsert_results(path, building_map, district_map, isd_map) do
    stream_as_maps(path)
    |> Stream.map(&tag_row(&1, building_map, district_map, isd_map))
    |> Stream.reject(&is_nil/1)
    |> Stream.chunk_every(@batch_size)
    |> Enum.reduce({0, 0}, fn batch, {ok_acc, err_acc} ->
      {building_rows, district_rows, isd_rows} =
        Enum.reduce(batch, {[], [], []}, fn
          {:building, attrs}, {b, d, i} -> {[attrs | b], d, i}
          {:district, attrs}, {b, d, i} -> {b, [attrs | d], i}
          {:isd, attrs}, {b, d, i} -> {b, d, [attrs | i]}
        end)

      r1 = bulk_upsert(building_rows, :upsert)
      r2 = bulk_upsert(district_rows, :upsert_district_rollup)
      r3 = bulk_upsert(isd_rows, :upsert_isd_rollup)

      total_ok =
        (length(building_rows) - r1.error_count) +
          (length(district_rows) - r2.error_count) +
          (length(isd_rows) - r3.error_count)

      {ok_acc + total_ok, err_acc + r1.error_count + r2.error_count + r3.error_count}
    end)
  end

  # Tags one CSV row as {:building, attrs}, {:district, attrs}, {:isd, attrs}, or nil.
  # Routing logic:
  #   district_code == "0"  → ISD-level aggregate
  #   building_code == "0"  → district-level aggregate
  #   otherwise             → building-level row
  defp tag_row(row, building_map, district_map, isd_map) do
    building_code = row["BuildingCode"]
    district_code = row["DistrictCode"]
    isd_code = row["ISDCode"]
    base = to_score_attrs(row)

    cond do
      district_code == "0" ->
        mde_isd_id = Map.get(isd_map, isd_code)

        if is_nil(mde_isd_id),
          do: nil,
          else: {:isd, Map.merge(base, %{mde_isd_id: mde_isd_id, rollup_level: :isd})}

      building_code == "0" ->
        mde_district_id = Map.get(district_map, district_code)

        if is_nil(mde_district_id),
          do: nil,
          else:
            {:district,
             Map.merge(base, %{mde_district_id: mde_district_id, rollup_level: :district})}

      true ->
        mde_building_id = Map.get(building_map, building_code)

        if is_nil(mde_building_id),
          do: nil,
          else:
            {:building,
             Map.merge(base, %{mde_building_id: mde_building_id, rollup_level: :building})}
    end
  end

  # Extracts all dimension + score fields from a CSV row (no FK resolution).
  defp to_score_attrs(row) do
    %{
      school_year: row["SchoolYear"],
      test_type: row["TestType"],
      test_population: row["TestPopulation"],
      grade_content_tested: row["GradeContentTested"],
      subject: row["Subject"],
      report_category: row["ReportCategory"],
      total_advanced: parse_integer(row["TotalAdvanced"]),
      total_proficient: parse_integer(row["TotalProficient"]),
      total_partially_proficient: parse_integer(row["TotalPartiallyProficient"]),
      total_not_proficient: parse_integer(row["TotalNotProficient"]),
      total_surpassed: parse_integer(row["TotalSurpassed"]),
      total_attained: parse_integer(row["TotalAttained"]),
      total_emerging_towards: parse_integer(row["TotalEmergingTowards"]),
      total_met: parse_integer(row["TotalMet"]),
      total_did_not_meet: parse_integer(row["TotalDidNotMeet"]),
      number_assessed: parse_integer(row["NumberAssessed"]),
      percent_advanced: parse_decimal(row["PercentAdvanced"]),
      percent_proficient: parse_decimal(row["PercentProficient"]),
      percent_partially_proficient: parse_decimal(row["PercentPartiallyProficient"]),
      percent_not_proficient: parse_decimal(row["PercentNotProficient"]),
      percent_surpassed: parse_decimal(row["PercentSurpassed"]),
      percent_attained: parse_decimal(row["PercentAttained"]),
      percent_emerging_towards: parse_decimal(row["PercentEmergingTowards"]),
      percent_met: parse_decimal(row["PercentMet"]),
      percent_did_not_meet: parse_decimal(row["PercentDidNotMeet"]),
      avg_ss: parse_decimal(row["AvgSS"]),
      std_dev_ss: parse_decimal(row["StdDevSS"]),
      mean_pts_earned: parse_decimal(row["MeanPtsEarned"]),
      min_scale_score: parse_decimal(row["MinScaleScore"]),
      max_scale_score: parse_decimal(row["MaxScaleScore"]),
      scale_score_25: parse_decimal(row["ScaleScore25"]),
      scale_score_50: parse_decimal(row["ScaleScore50"]),
      scale_score_75: parse_decimal(row["ScaleScore75"])
    }
  end

  # ---------------------------------------------------------------------------
  # Bulk upsert helper
  # ---------------------------------------------------------------------------

  defp bulk_upsert([], _action), do: %{error_count: 0}

  defp bulk_upsert(rows, action) do
    Ash.bulk_create(rows, MdeStateAssessmentResult, action,
      authorize?: false,
      return_errors?: true,
      upsert_fields: @score_upsert_fields
    )
  end

  # ---------------------------------------------------------------------------
  # Post-upsert lookup helper
  # ---------------------------------------------------------------------------

  # Reads an entire dimension table and returns a map of code_value → UUID.
  defp build_code_map(resource, code_field) do
    resource
    |> Ash.read!(authorize?: false)
    |> Map.new(fn record -> {Map.get(record, code_field), record.id} end)
  end

  # ---------------------------------------------------------------------------
  # Value coercion helpers
  # ---------------------------------------------------------------------------

  defp validate_file(path) do
    if File.exists?(path),
      do: :ok,
      else: {:error, "File not found: #{path}"}
  end

  # Empty string and whitespace-only values from MDE CSV → nil
  defp nilify(val) when is_binary(val) do
    case String.trim(val) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp nilify(val), do: val

  # MDE suppresses cells below 10 students with empty strings
  defp parse_integer(val) when val in [nil, ""], do: nil

  defp parse_integer(val) when is_binary(val) do
    case Integer.parse(String.trim(val)) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp parse_decimal(val) when val in [nil, ""], do: nil

  defp parse_decimal(val) when is_binary(val) do
    case Decimal.parse(String.trim(val)) do
      {d, _} -> d
      :error -> nil
    end
  end
end
