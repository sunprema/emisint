defmodule Emisint.Assessments.MdeSgpImporter do
  @batch_size 500

  @moduledoc """
  Imports MDE Student Growth Percentile (SGP) CSV data into the
  `mde_sgp_results` table.

  The SGP export mixes statewide/ISD/district/building aggregation levels in
  the same columns (same `0`/Statewide-code convention as `mde_importer.ex`).
  This importer keeps **building-level and district-level (LEA) rows** —
  ISD/statewide aggregate rows (blank or `"0"` DistrictCode) are skipped, since
  nothing in the app currently needs ISD-level SGP.

  Grain: (building or district) × school year × grade × subject × testing
  group (subgroup). Subject is stored as free text — MDE's file includes
  Mathematics, English Language Arts, Science, and Social Studies, but nothing
  is hardcoded so additional subjects import cleanly too.

  Small-enrollment cells are privacy-suppressed in the source file (e.g.
  `< 10`, `< 5` instead of a real count/percent). Those are parsed to `nil`
  rather than stored as text.

  ## Pipeline

    1. **First pass** — stream the CSV to collect unique ISDs and districts
       from every row with a real DistrictCode, and buildings from rows that
       also have a real BuildingCode.
    2. **Upsert dimension tables** in FK order: `MdeIsd → MdeDistrict → MdeBuilding`.
    3. **Second pass** — stream fact rows in batches of #{@batch_size}, tag
       each as building-level or district-level rollup, resolve the building
       or district UUID, and bulk-upsert `MdeSgpResult` via the matching
       upsert action (building and district rows in a batch run in parallel).

  ## Expected CSV column headers

      SchoolYear, IsdCode, IsdName, DistrictCode, DistrictName,
      BuildingCode, BuildingName, CountyCode, CountyName, EntityType,
      SchoolLevel, Locale, MISTEM_NAME, MISTEM_CODE,
      Grade, Subject, TestingGroup,
      NumberAboveAverageGrowth, NumberAverageGrowth, NumberBelowAverageGrowth,
      PercentAboveAverage, PercentAverageGrowth, PercentBelowAverage,
      TotalIncluded, MeanSGP

  ## Usage

      iex> Emisint.Assessments.MdeSgpImporter.import_file("priv/data/2024-25_SGP_Results.csv")
      {:ok, %{records: 12_400, errors: 0, school_year: "2024-2025", error_file: nil}}

  """

  alias Emisint.Assessments.{MdeBuilding, MdeDistrict, MdeIsd, MdeSgpResult}

  @upsert_fields [
    :testing_group,
    :number_above_average_growth,
    :number_average_growth,
    :number_below_average_growth,
    :percent_above_average,
    :percent_average_growth,
    :percent_below_average,
    :total_included,
    :mean_sgp
  ]

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
        upsert_results(path, building_map, district_map, school_year)

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
        headers = [String.trim_leading(first, "﻿") | rest]
        {[], headers}

      row, headers ->
        row_map = headers |> Enum.zip(row) |> Map.new()
        {[row_map], headers}
    end)
  end

  # ---------------------------------------------------------------------------
  # First pass — collect unique dimension records.
  #
  # District (and its parent ISD) is collected from every row with a real
  # DistrictCode — both building-level rows and district-rollup rows share the
  # same district. Building is only collected when the row also has a real
  # BuildingCode. Rows with no district code (ISD/statewide aggregates) are
  # skipped entirely — out of scope for this importer.
  # ---------------------------------------------------------------------------

  defp collect_dimensions(path) do
    stream_as_maps(path)
    |> Enum.reduce({%{}, %{}, %{}, nil}, fn row, {isds, districts, buildings, school_year} ->
      district_code = normalize_entity_code(nilify(row["DistrictCode"]))

      if is_nil(district_code) or district_code == "0" do
        {isds, districts, buildings, school_year}
      else
        building_code = normalize_entity_code(nilify(row["BuildingCode"]))
        isd_code = normalize_entity_code(row["IsdCode"])
        school_year = school_year || nilify(row["SchoolYear"])

        isds =
          Map.put_new(isds, isd_code, %{
            isd_code: isd_code,
            isd_name: row["IsdName"]
          })

        districts =
          Map.put_new(districts, district_code, %{
            district_code: district_code,
            district_name: row["DistrictName"],
            county_code: nilify(row["CountyCode"]),
            county_name: nilify(row["CountyName"]),
            entity_type: nilify(row["EntityType"]),
            isd_code: isd_code
          })

        buildings =
          if is_nil(building_code) or building_code == "0" do
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
      end
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
  # Second pass — stream fact rows in batches, tagged building or district
  # ---------------------------------------------------------------------------

  defp upsert_results(path, building_map, district_map, school_year) do
    stream_as_maps(path)
    |> Stream.map(&to_sgp_attrs(&1, building_map, district_map, school_year))
    |> Stream.reject(&is_nil/1)
    |> Stream.chunk_every(@batch_size)
    |> Enum.reduce({0, 0, []}, fn batch, {ok_acc, err_acc, err_rows_acc} ->
      {building_rows, district_rows} = Enum.split_with(batch, &(&1.rollup_level == :building))

      [b, d] =
        [
          Task.async(fn -> bulk_upsert(building_rows, :upsert) end),
          Task.async(fn -> bulk_upsert(district_rows, :upsert_district_rollup) end)
        ]
        |> Task.await_many(120_000)

      batch_ok = length(building_rows) - b.error_count + length(district_rows) - d.error_count
      batch_errors = b.error_count + d.error_count

      {ok_acc + batch_ok, err_acc + batch_errors, err_rows_acc ++ b.error_rows ++ d.error_rows}
    end)
  end

  defp bulk_upsert([], _action), do: %{error_count: 0, error_rows: []}

  defp bulk_upsert(rows, action) do
    result =
      Ash.bulk_create(rows, MdeSgpResult, action,
        authorize?: false,
        return_errors?: true,
        upsert_fields: @upsert_fields
      )

    error_rows =
      if result.error_count > 0 do
        Enum.filter(rows, fn attrs ->
          r =
            Ash.bulk_create([attrs], MdeSgpResult, action,
              authorize?: false,
              return_errors?: true,
              upsert_fields: @upsert_fields
            )

          r.error_count > 0
        end)
      else
        []
      end

    %{error_count: result.error_count, error_rows: error_rows}
  end

  # Maps one CSV row to a tagged attrs map (rollup_level: :building or
  # :district), resolving the building/district UUID via the dimension maps.
  # Returns nil for ISD/statewide rows (no district code) or when the
  # building/district isn't in the dimension map.
  defp to_sgp_attrs(row, building_map, district_map, school_year) do
    district_code = normalize_entity_code(nilify(row["DistrictCode"]))
    building_code = normalize_entity_code(nilify(row["BuildingCode"]))

    cond do
      is_nil(district_code) or district_code == "0" ->
        nil

      is_nil(building_code) or building_code == "0" ->
        case Map.get(district_map, district_code) do
          nil ->
            nil

          mde_district_id ->
            base_sgp_attrs(row, school_year,
              rollup_level: :district,
              mde_district_id: mde_district_id
            )
        end

      true ->
        case Map.get(building_map, building_code) do
          nil ->
            nil

          mde_building_id ->
            base_sgp_attrs(row, school_year,
              rollup_level: :building,
              mde_building_id: mde_building_id
            )
        end
    end
  end

  defp base_sgp_attrs(row, school_year, extra) do
    %{
      school_year: nilify(row["SchoolYear"]) || school_year,
      grade: nilify(row["Grade"]),
      subject: nilify(row["Subject"]),
      testing_group: nilify(row["TestingGroup"]),
      number_above_average_growth: parse_suppressible_integer(row["NumberAboveAverageGrowth"]),
      number_average_growth: parse_suppressible_integer(row["NumberAverageGrowth"]),
      number_below_average_growth: parse_suppressible_integer(row["NumberBelowAverageGrowth"]),
      percent_above_average: parse_suppressible_decimal(row["PercentAboveAverage"]),
      percent_average_growth: parse_suppressible_decimal(row["PercentAverageGrowth"]),
      percent_below_average: parse_suppressible_decimal(row["PercentBelowAverage"]),
      total_included: parse_suppressible_integer(row["TotalIncluded"]),
      mean_sgp: parse_suppressible_decimal(row["MeanSGP"])
    }
    |> Map.merge(Map.new(extra))
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

  # Strips MDE zero-padding from entity codes so they match codes already
  # stored by the assessment importer (e.g. "03000" → "3000", "00520" → "520").
  # nil passes through unchanged.
  defp normalize_entity_code(nil), do: nil

  defp normalize_entity_code(code) do
    case String.trim_leading(code, "0") do
      "" -> "0"
      stripped -> stripped
    end
  end

  # Empty string and whitespace-only values → nil
  defp nilify(val) when is_binary(val) do
    case String.trim(val) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp nilify(val), do: val

  # Privacy-suppressed cells arrive as text like "< 10" or "< 5" — parsed to
  # nil rather than stored, same treatment as blank/NA values.
  defp suppressed?(val) when is_binary(val), do: String.trim(val) |> String.starts_with?("<")
  defp suppressed?(_), do: false

  defp parse_suppressible_integer(nil), do: nil

  defp parse_suppressible_integer(val) when is_binary(val) do
    if suppressed?(val) do
      nil
    else
      case val |> String.trim() |> String.replace(",", "") |> Integer.parse() do
        {int, _rest} -> int
        :error -> nil
      end
    end
  end

  defp parse_suppressible_decimal(nil), do: nil

  defp parse_suppressible_decimal(val) when is_binary(val) do
    if suppressed?(val) do
      nil
    else
      case val |> String.trim() |> String.replace("%", "") |> Decimal.parse() do
        {d, ""} -> d
        _ -> nil
      end
    end
  end
end
