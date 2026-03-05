defmodule Emisint.Assessments.MdeSatImporter do
  @batch_size 500

  @moduledoc """
  Imports MDE SAT college-readiness CSV data into the `mde_sat_results` table.

  SAT files contain building-, district-, and ISD-level aggregate rows broken out
  by ESSA subgroup. Unlike the enrollment CSV (which uses blank fields for rollups),
  this file uses the same zero-sentinel convention as the MDE state assessment CSV:
  `DistrictCode = "0"` signals an ISD-level row and `BuildingCode = "0"` signals a
  district-level row.

  The CSV is **wide-format** — one row per entity × school year × subgroup, with all
  subject metrics (Math, Reading, Science, English, AllSubject, EBRW) as columns.

  ## Pipeline

    1. **First pass** — stream the CSV to collect unique ISDs, districts, and buildings.
       Rows with sentinel codes are skipped when collecting lower-level dimensions.
    2. **Upsert dimension tables** in FK order:
       `MdeIsd → MdeDistrict → MdeBuilding`
       After each upsert, build a `code → UUID` lookup map.
    3. **Second pass** — stream fact rows in batches of #{@batch_size}, tag each as
       `:building`, `:district`, or `:isd`, resolve UUIDs, and bulk-upsert
       `MdeSatResult` via the appropriate action.

  ## Expected CSV column headers

      SchoolYear, ISDCode, ISDName, DistrictCode, DistrictName,
      BuildingCode, BuildingName, CountyCode, CountyName, EntityType,
      SchoolLevel, Locale, MISTEM_NAME, MISTEM_CODE, Subgroup,
      MathPercentReady, MathNumAssessed, MathScoreAverage, MathCountReady,
      ReadingPercentReady, ReadingNumAssessed, ReadingScoreAverage,
      SciencePercentReady, ScienceNumAssessed, ScienceScoreAverage,
      EnglishPercentReady, EnglishNumAssessed, EnglishScoreAverage,
      AllSubjectPercentReady, AllSubjectNumAssessed, AllSubjectScoreAverage, AllCountReady,
      EBRWPercentReady, EBRWNumAssessed, EBRWScoreAverage, EBRWCountReady

  ## Usage

      iex> Emisint.Assessments.MdeSatImporter.import_file("/tmp/sat_2024.csv")
      {:ok, %{records: 2450, errors: 0, school_year: "2023-2024"}}

  """

  alias Emisint.Assessments.{MdeBuilding, MdeDistrict, MdeIsd, MdeSatResult}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec import_file(Path.t()) :: {:ok, map()} | {:error, String.t()}
  def import_file(path) do
    with :ok <- validate_file(path) do
      {isds, districts, buildings, school_year} = collect_dimensions(path)

      upsert_isds(isds)
      isd_map = build_code_map(MdeIsd, :isd_code)

      upsert_districts(districts, isd_map)
      district_map = build_code_map(MdeDistrict, :district_code)

      upsert_buildings(buildings, district_map)
      building_map = build_code_map(MdeBuilding, :building_code)

      {record_count, error_count, error_rows} =
        upsert_results(path, building_map, district_map, isd_map)

      error_file = write_error_csv(path, error_rows)

      {:ok,
       %{
         records: record_count,
         errors: error_count,
         school_year: school_year,
         error_file: error_file
       }}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  # ---------------------------------------------------------------------------
  # Streaming helpers
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
  # First pass — collect unique dimension records
  # ---------------------------------------------------------------------------

  defp collect_dimensions(path) do
    stream_as_maps(path)
    |> Enum.reduce({%{}, %{}, %{}, nil}, fn row, {isds, districts, buildings, school_year} ->
      isd_code = row["ISDCode"]
      district_code = row["DistrictCode"]
      building_code = row["BuildingCode"]

      school_year = school_year || nilify(row["SchoolYear"])

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
            district_code: district_code
          })
        end

      {isds, districts, buildings, school_year}
    end)
  end

  # ---------------------------------------------------------------------------
  # Dimension upserts (reuses existing MdeIsd/MdeDistrict/MdeBuilding actions)
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
    |> Enum.reduce({0, 0, []}, fn batch, {ok_acc, err_acc, err_rows_acc} ->
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

      batch_err_rows = r1.error_rows ++ r2.error_rows ++ r3.error_rows

      {ok_acc + total_ok,
       err_acc + r1.error_count + r2.error_count + r3.error_count,
       err_rows_acc ++ batch_err_rows}
    end)
  end

  # Tags one row as {:building, attrs}, {:district, attrs}, {:isd, attrs}, or nil.
  # Routing logic (zero = rollup sentinel, same as MDE state assessment CSV):
  #   district_code == "0" → ISD-level aggregate
  #   building_code == "0" (district != "0") → district-level aggregate
  #   otherwise → building-level row
  defp tag_row(row, building_map, district_map, isd_map) do
    district_code = row["DistrictCode"]
    building_code = row["BuildingCode"]
    isd_code = row["ISDCode"]
    base = to_sat_attrs(row)

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

  # Extracts dimension strings + all SAT metric columns from a CSV row.
  defp to_sat_attrs(row) do
    %{
      school_year: nilify(row["SchoolYear"]),
      subgroup: nilify(row["Subgroup"]),
      isd_code: nilify(row["ISDCode"]),
      isd_name: nilify(row["ISDName"]),
      district_code: nilify(row["DistrictCode"]),
      district_name: nilify(row["DistrictName"]),
      building_code: nilify(row["BuildingCode"]),
      building_name: nilify(row["BuildingName"]),
      county_code: nilify(row["CountyCode"]),
      county_name: nilify(row["CountyName"]),
      entity_type: nilify(row["EntityType"]),
      school_level: nilify(row["SchoolLevel"]),
      locale: nilify(row["Locale"]),
      mistem_name: nilify(row["MISTEM_NAME"]),
      mistem_code: nilify(row["MISTEM_CODE"]),
      math_percent_ready: parse_decimal(row["MathPercentReady"]),
      math_num_assessed: parse_integer(row["MathNumAssessed"]),
      math_score_average: parse_decimal(row["MathScoreAverage"]),
      math_count_ready: parse_integer(row["MathCountReady"]),
      reading_percent_ready: parse_decimal(row["ReadingPercentReady"]),
      reading_num_assessed: parse_integer(row["ReadingNumAssessed"]),
      reading_score_average: parse_decimal(row["ReadingScoreAverage"]),
      science_percent_ready: parse_decimal(row["SciencePercentReady"]),
      science_num_assessed: parse_integer(row["ScienceNumAssessed"]),
      science_score_average: parse_decimal(row["ScienceScoreAverage"]),
      english_percent_ready: parse_decimal(row["EnglishPercentReady"]),
      english_num_assessed: parse_integer(row["EnglishNumAssessed"]),
      english_score_average: parse_decimal(row["EnglishScoreAverage"]),
      all_subject_percent_ready: parse_decimal(row["AllSubjectPercentReady"]),
      all_subject_num_assessed: parse_integer(row["AllSubjectNumAssessed"]),
      all_subject_score_average: parse_decimal(row["AllSubjectScoreAverage"]),
      all_count_ready: parse_integer(row["AllCountReady"]),
      ebrw_percent_ready: parse_decimal(row["EBRWPercentReady"]),
      ebrw_num_assessed: parse_integer(row["EBRWNumAssessed"]),
      ebrw_score_average: parse_decimal(row["EBRWScoreAverage"]),
      ebrw_count_ready: parse_integer(row["EBRWCountReady"])
    }
  end

  # ---------------------------------------------------------------------------
  # Bulk upsert helper
  # ---------------------------------------------------------------------------

  defp bulk_upsert([], _action), do: %{error_count: 0, error_rows: []}

  defp bulk_upsert(rows, action) do
    result =
      Ash.bulk_create(rows, MdeSatResult, action,
        authorize?: false,
        return_errors?: true
      )

    error_rows =
      if result.error_count > 0 do
        Enum.filter(rows, fn row ->
          r = Ash.bulk_create([row], MdeSatResult, action, authorize?: false, return_errors?: true)
          r.error_count > 0
        end)
      else
        []
      end

    %{error_count: result.error_count, error_rows: error_rows}
  end

  # ---------------------------------------------------------------------------
  # Post-upsert lookup helper
  # ---------------------------------------------------------------------------

  defp build_code_map(resource, code_field) do
    resource
    |> Ash.read!(authorize?: false)
    |> Map.new(fn record -> {Map.get(record, code_field), record.id} end)
  end

  # ---------------------------------------------------------------------------
  # Error CSV writer
  # ---------------------------------------------------------------------------

  # Writes error rows to a sibling CSV file. Returns the path, or nil if no errors.
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

  # MDE suppresses small cells with empty strings
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
