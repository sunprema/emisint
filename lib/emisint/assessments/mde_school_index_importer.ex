defmodule Emisint.Assessments.MdeSchoolIndexImporter do
  @batch_size 500

  @moduledoc """
  Imports MDE School Index Results CSV data into the `mde_school_index_results` table.

  School Index files are published annually by MDE and contain building-level
  accountability index scores (overall, growth, proficiency, graduation, EL progress,
  school quality, participation, and support category).

  Unlike other MDE importers, **all rows are building-level only** — there are no
  district or ISD rollup rows to filter.

  SchoolYear is formatted as `"2024-2025"` (not `"24-25 School Year"` like enrollment).
  Entity codes are 5-char zero-padded MDE format — strip leading zeros before lookup.
  `"--"` values mean not applicable and are stored as nil.

  ## Pipeline

    1. **First pass** — stream the CSV to collect unique ISDs, districts, and buildings.
    2. **Upsert dimension tables** in FK order:
       `MdeIsd → MdeDistrict → MdeBuilding`
       After each upsert, build a `code → UUID` lookup map.
    3. **Second pass** — stream fact rows in batches of #{@batch_size}, resolve
       building UUID, and bulk-upsert `MdeSchoolIndexResult` via the `:upsert` action.

  ## Expected CSV column headers

      SchoolYear, ISDCode, ISDName, DistrictCode, DistrictName,
      BuildingCode, BuildingName, CountyCode, CountyName, EntityType,
      SchoolLevel, LOCALE_NAME, MISTEM_NAME, MISTEM_CODE,
      OverallIndex, GrowthIndex, ProficiencyIndex, GraduationIndex,
      ELProgressIndex, SchoolQualityIndex, SubjectParticipationIndex,
      ELParticipationIndex, SupportCategoryName, SupportCategoryReason

  ## Usage

      iex> Emisint.Assessments.MdeSchoolIndexImporter.import_file("priv/data/2024-25_School_Index_Results.csv")
      {:ok, %{records: 850, errors: 0, school_year: "2024-2025", error_file: nil}}

  """

  alias Emisint.Assessments.{MdeBuilding, MdeDistrict, MdeIsd, MdeSchoolIndexResult}

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

      {record_count, error_count, error_rows} = upsert_results(path, building_map, school_year)

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
      building_code = normalize_entity_code(nilify(row["BuildingCode"]))

      # Skip rows with no building code
      if is_nil(building_code) do
        {isds, districts, buildings, school_year}
      else
        isd_code = normalize_entity_code(row["ISDCode"])
        district_code = normalize_entity_code(nilify(row["DistrictCode"]))

        school_year = school_year || nilify(row["SchoolYear"])

        isds =
          Map.put_new(isds, isd_code, %{
            isd_code: isd_code,
            isd_name: row["ISDName"]
          })

        districts =
          if district_code == nil do
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

        buildings =
          if district_code == nil do
            buildings
          else
            Map.put_new(buildings, building_code, %{
              building_code: building_code,
              building_name: row["BuildingName"],
              school_level: nilify(row["SchoolLevel"]),
              locale: nilify(row["LOCALE_NAME"]),
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
  # Second pass — stream fact rows in batches
  # ---------------------------------------------------------------------------

  defp upsert_results(path, building_map, school_year) do
    stream_as_maps(path)
    |> Stream.map(&to_index_attrs(&1, building_map, school_year))
    |> Stream.reject(&is_nil/1)
    |> Stream.chunk_every(@batch_size)
    |> Enum.reduce({0, 0, []}, fn batch, {ok_acc, err_acc, err_rows_acc} ->
      result =
        Ash.bulk_create(batch, MdeSchoolIndexResult, :upsert,
          authorize?: false,
          return_errors?: true,
          upsert_fields: [
            :overall_index,
            :growth_index,
            :proficiency_index,
            :graduation_index,
            :el_progress_index,
            :school_quality_index,
            :subject_participation_index,
            :el_participation_index,
            :support_category_name,
            :support_category_reason
          ]
        )

      batch_error_rows =
        if result.error_count > 0 do
          Enum.filter(batch, fn attrs ->
            r =
              Ash.bulk_create([attrs], MdeSchoolIndexResult, :upsert,
                authorize?: false,
                return_errors?: true,
                upsert_fields: [
                  :overall_index,
                  :growth_index,
                  :proficiency_index,
                  :graduation_index,
                  :el_progress_index,
                  :school_quality_index,
                  :subject_participation_index,
                  :el_participation_index,
                  :support_category_name,
                  :support_category_reason
                ]
              )

            r.error_count > 0
          end)
        else
          []
        end

      batch_ok = length(batch) - result.error_count

      {ok_acc + batch_ok, err_acc + result.error_count, err_rows_acc ++ batch_error_rows}
    end)
  end

  # Maps one CSV row to an attrs map, resolving building UUID via building_map.
  # Returns nil if building_code is blank or unknown.
  defp to_index_attrs(row, building_map, school_year) do
    building_code = normalize_entity_code(nilify(row["BuildingCode"]))

    case building_code && Map.get(building_map, building_code) do
      nil ->
        nil

      mde_building_id ->
        %{
          school_year: nilify(row["SchoolYear"]) || school_year,
          mde_building_id: mde_building_id,
          overall_index: parse_decimal(row["OverallIndex"]),
          growth_index: parse_decimal(row["GrowthIndex"]),
          proficiency_index: parse_decimal(row["ProficiencyIndex"]),
          graduation_index: parse_decimal(row["GraduationIndex"]),
          el_progress_index: parse_decimal(row["ELProgressIndex"]),
          school_quality_index: parse_decimal(row["SchoolQualityIndex"]),
          subject_participation_index: parse_decimal(row["SubjectParticipationIndex"]),
          el_participation_index: parse_decimal(row["ELParticipationIndex"]),
          support_category_name: nilify(row["SupportCategoryName"]),
          support_category_reason: nilify(row["SupportCategoryReason"])
        }
    end
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

  # Returns nil for "--" (not applicable), empty strings, or nil.
  defp parse_decimal(val) when val in [nil, "", "--"], do: nil

  defp parse_decimal(val) when is_binary(val) do
    case Decimal.parse(String.trim(val)) do
      {d, ""} -> d
      _ -> nil
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
end
