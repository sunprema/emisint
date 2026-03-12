defmodule Emisint.Assessments.MdeImporter do
  @batch_size 5000

  @moduledoc """
  Imports MDE public state assessment CSV data into the normalized relational tables.

  The CSV must follow the standard MDE aggregate export format with a header row.
  File may be very large (millions of rows); the importer uses a **single streaming
  pass** so the file is read exactly once.

  ## Pipeline

    1. **Single pass** — stream the CSV in batches of #{@batch_size} rows.
       For each batch:
       a. Extract any dimension records (ISDs, districts, buildings) not yet seen.
       b. Upsert only the *new* dimensions in FK order, then extend the in-memory
          `code → UUID` lookup maps with just the new entries (no full table re-read).
       c. Tag fact rows by rollup granularity, resolve UUIDs, and bulk-upsert via
          three parallel tasks.

    Dimension sets are tiny (~57 ISDs, ~900 districts, ~4 000 buildings statewide)
    and stabilise within the first few batches; subsequent batches skip dimension
    upserts entirely.

  ## Usage

      iex> Emisint.Assessments.MdeImporter.import_file("priv/data/mde_assessment_results.csv")
      {:ok, %{isds: 57, districts: 842, buildings: 3891, results: 1_200_000, errors: 0}}

  """

  require Ash.Query
  require Logger

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
    :percent_met_suppressed,
    :percent_met_approximate,
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
      initial_state = %{
        seen_isd_codes: MapSet.new(),
        seen_district_codes: MapSet.new(),
        seen_building_codes: MapSet.new(),
        isd_map: %{},
        district_map: %{},
        building_map: %{},
        school_year: nil,
        batch_num: 0,
        import_start: System.monotonic_time(:millisecond)
      }

      {result_count, error_count, error_rows, final_state} =
        stream_as_maps(path)
        |> Stream.chunk_every(@batch_size)
        |> Enum.reduce({0, 0, [], initial_state}, &process_batch/2)

      error_file = write_error_csv(path, error_rows)

      {:ok,
       %{
         isds: MapSet.size(final_state.seen_isd_codes),
         districts: MapSet.size(final_state.seen_district_codes),
         buildings: MapSet.size(final_state.seen_building_codes),
         results: result_count,
         errors: error_count,
         school_year: final_state.school_year,
         error_file: error_file
       }}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  # ---------------------------------------------------------------------------
  # Batch processor — single pass
  # ---------------------------------------------------------------------------

  defp process_batch(batch, {ok_acc, err_acc, err_rows_acc, state}) do
    batch_num = state.batch_num + 1
    batch_start = System.monotonic_time(:millisecond)

    # Capture school_year from the first row that has one
    school_year =
      state.school_year ||
        Enum.find_value(batch, fn row -> row["SchoolYear"] end)

    # Extract dimensions from this batch that we haven't seen before
    {new_isds, new_districts, new_buildings} = extract_new_dims(batch, state)

    # Upsert only the newly discovered dimensions and extend the lookup maps
    state =
      state
      |> maybe_upsert_isds(new_isds)
      |> maybe_upsert_districts(new_districts)
      |> maybe_upsert_buildings(new_buildings)
      |> Map.put(:school_year, school_year)
      |> Map.put(:batch_num, batch_num)

    # Tag fact rows and upsert in parallel by rollup granularity
    {building_rows, district_rows, isd_rows} =
      Enum.reduce(batch, {[], [], []}, fn row, {b, d, i} ->
        case tag_row(row, state.building_map, state.district_map, state.isd_map) do
          {:building, attrs} -> {[attrs | b], d, i}
          {:district, attrs} -> {b, [attrs | d], i}
          {:isd, attrs} -> {b, d, [attrs | i]}
          nil -> {b, d, i}
        end
      end)

    [r1, r2, r3] =
      [
        Task.async(fn -> bulk_upsert(building_rows, :upsert) end),
        Task.async(fn -> bulk_upsert(district_rows, :upsert_district_rollup) end),
        Task.async(fn -> bulk_upsert(isd_rows, :upsert_isd_rollup) end)
      ]
      |> Task.await_many(120_000)

    total_ok =
      (length(building_rows) - r1.error_count) +
        (length(district_rows) - r2.error_count) +
        (length(isd_rows) - r3.error_count)

    batch_ms = System.monotonic_time(:millisecond) - batch_start
    elapsed_ms = System.monotonic_time(:millisecond) - state.import_start
    rows_done = ok_acc + total_ok

    Logger.info(
      "[MdeImporter] Batch #{batch_num} — #{length(batch)} rows in #{batch_ms}ms" <>
        " | total: #{rows_done} rows, #{div(elapsed_ms, 1000)}s elapsed" <>
        " | dims: #{MapSet.size(state.seen_isd_codes)} ISDs," <>
        " #{MapSet.size(state.seen_district_codes)} districts," <>
        " #{MapSet.size(state.seen_building_codes)} buildings"
    )

    {ok_acc + total_ok,
     err_acc + r1.error_count + r2.error_count + r3.error_count,
     err_rows_acc ++ r1.error_rows ++ r2.error_rows ++ r3.error_rows, state}
  end

  # ---------------------------------------------------------------------------
  # Incremental dimension extraction
  # ---------------------------------------------------------------------------

  defp extract_new_dims(batch, state) do
    Enum.reduce(batch, {%{}, %{}, %{}}, fn row, {new_isds, new_districts, new_buildings} ->
      isd_code = row["ISDCode"]
      district_code = row["DistrictCode"]
      building_code = row["BuildingCode"]

      new_isds =
        if isd_code && not MapSet.member?(state.seen_isd_codes, isd_code) do
          Map.put_new(new_isds, isd_code, %{
            isd_code: isd_code,
            isd_name: row["ISDName"]
          })
        else
          new_isds
        end

      new_districts =
        if district_code && district_code != "0" &&
             not MapSet.member?(state.seen_district_codes, district_code) do
          Map.put_new(new_districts, district_code, %{
            district_code: district_code,
            district_name: row["DistrictName"],
            county_code: nilify(row["CountyCode"]),
            county_name: nilify(row["CountyName"]),
            entity_type: nilify(row["EntityType"]),
            isd_code: isd_code
          })
        else
          new_districts
        end

      new_buildings =
        if building_code && building_code != "0" &&
             not MapSet.member?(state.seen_building_codes, building_code) do
          Map.put_new(new_buildings, building_code, %{
            building_code: building_code,
            building_name: row["BuildingName"],
            school_level: nilify(row["SchoolLevel"]),
            locale: nilify(row["Locale"]),
            mistem_name: nilify(row["MISTEM_NAME"]),
            mistem_code: nilify(row["MISTEM_CODE"]),
            district_code: district_code
          })
        else
          new_buildings
        end

      {new_isds, new_districts, new_buildings}
    end)
  end

  # ---------------------------------------------------------------------------
  # Incremental dimension upserts — only called when new codes are found
  # ---------------------------------------------------------------------------

  defp maybe_upsert_isds(state, new_isds) when map_size(new_isds) == 0, do: state

  defp maybe_upsert_isds(state, new_isds) do
    new_isds
    |> Map.values()
    |> Ash.bulk_create(MdeIsd, :upsert,
      authorize?: false,
      return_errors?: true,
      upsert_fields: [:isd_name]
    )

    new_codes = Map.keys(new_isds)

    new_entries =
      MdeIsd
      |> Ash.Query.filter(isd_code in ^new_codes)
      |> Ash.read!(authorize?: false)
      |> Map.new(fn r -> {r.isd_code, r.id} end)

    %{
      state
      | seen_isd_codes: MapSet.union(state.seen_isd_codes, MapSet.new(new_codes)),
        isd_map: Map.merge(state.isd_map, new_entries)
    }
  end

  defp maybe_upsert_districts(state, new_districts) when map_size(new_districts) == 0,
    do: state

  defp maybe_upsert_districts(state, new_districts) do
    new_districts
    |> Map.values()
    |> Enum.map(fn d ->
      d
      |> Map.put(:mde_isd_id, Map.get(state.isd_map, d.isd_code))
      |> Map.delete(:isd_code)
    end)
    |> Ash.bulk_create(MdeDistrict, :upsert,
      authorize?: false,
      return_errors?: true,
      upsert_fields: [:district_name, :county_code, :county_name, :entity_type, :mde_isd_id]
    )

    new_codes = Map.keys(new_districts)

    new_entries =
      MdeDistrict
      |> Ash.Query.filter(district_code in ^new_codes)
      |> Ash.read!(authorize?: false)
      |> Map.new(fn r -> {r.district_code, r.id} end)

    %{
      state
      | seen_district_codes: MapSet.union(state.seen_district_codes, MapSet.new(new_codes)),
        district_map: Map.merge(state.district_map, new_entries)
    }
  end

  defp maybe_upsert_buildings(state, new_buildings) when map_size(new_buildings) == 0,
    do: state

  defp maybe_upsert_buildings(state, new_buildings) do
    new_buildings
    |> Map.values()
    |> Enum.map(fn b ->
      b
      |> Map.put(:mde_district_id, Map.get(state.district_map, b.district_code))
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

    new_codes = Map.keys(new_buildings)

    new_entries =
      MdeBuilding
      |> Ash.Query.filter(building_code in ^new_codes)
      |> Ash.read!(authorize?: false)
      |> Map.new(fn r -> {r.building_code, r.id} end)

    %{
      state
      | seen_building_codes: MapSet.union(state.seen_building_codes, MapSet.new(new_codes)),
        building_map: Map.merge(state.building_map, new_entries)
    }
  end

  # ---------------------------------------------------------------------------
  # Streaming helper
  # ---------------------------------------------------------------------------

  defp stream_as_maps(path) do
    File.stream!(path)
    |> NimbleCSV.RFC4180.parse_stream(skip_headers: false)
    |> Stream.transform(nil, fn
      [first | rest], nil ->
        headers = [String.trim_leading(first, "\uFEFF") | rest]
        {[], headers}

      row, headers ->
        row_map = headers |> Enum.zip(row) |> Map.new()
        {[row_map], headers}
    end)
  end

  # ---------------------------------------------------------------------------
  # Row tagging
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Bulk upsert helper
  # ---------------------------------------------------------------------------

  defp bulk_upsert([], _action), do: %{error_count: 0, error_rows: []}

  defp bulk_upsert(rows, action) do
    result =
      Ash.bulk_create(rows, MdeStateAssessmentResult, action,
        authorize?: false,
        return_errors?: true,
        upsert_fields: @score_upsert_fields
      )

    %{error_count: result.error_count, error_rows: []}
  end

  # ---------------------------------------------------------------------------
  # Error CSV writer
  # ---------------------------------------------------------------------------

  defp write_error_csv(_path, []), do: nil

  defp write_error_csv(input_path, [first | _] = error_rows) do
    headers = first |> Map.keys() |> Enum.sort()
    header_strings = Enum.map(headers, &to_string/1)

    data_rows =
      Enum.map(error_rows, fn row ->
        Enum.map(headers, fn key -> to_string(row[key] || "") end)
      end)

    content = NimbleCSV.RFC4180.dump_to_iodata([header_strings | data_rows])

    base = Path.basename(input_path, ".csv")
    error_path = Path.join(Path.dirname(input_path), "#{base}_errors.csv")
    File.write!(error_path, content)
    error_path
  end

  # ---------------------------------------------------------------------------
  # Value coercion helpers
  # ---------------------------------------------------------------------------

  defp validate_file(path) do
    if File.exists?(path),
      do: :ok,
      else: {:error, "File not found: #{path}"}
  end

  defp nilify(val) when is_binary(val) do
    case String.trim(val) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp nilify(val), do: val

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

  defp suppressed?(val) when is_binary(val), do: String.trim(val) == "*"
  defp suppressed?(_), do: false

  @range_pattern ~r/^[<>]=?\s*(\d+(?:\.\d+)?)\s*%?$/

  defp approximate?(val) when is_binary(val) do
    trimmed = String.trim(val)
    trimmed != "*" && Regex.match?(@range_pattern, trimmed)
  end

  defp approximate?(_), do: false

  defp parse_suppressed_decimal(val) when is_binary(val) do
    case String.trim(val) do
      "*" -> nil
      trimmed -> trimmed |> strip_range_operators() |> parse_decimal()
    end
  end

  defp parse_suppressed_decimal(val), do: parse_decimal(val)

  defp strip_range_operators(val) do
    case Regex.run(@range_pattern, val, capture: :all_but_first) do
      [number] -> number
      nil -> val
    end
  end

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
      percent_met: parse_suppressed_decimal(row["PercentMet"]),
      percent_met_suppressed: suppressed?(row["PercentMet"]),
      percent_met_approximate: approximate?(row["PercentMet"]),
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
end
