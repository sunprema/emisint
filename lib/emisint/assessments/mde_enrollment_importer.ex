defmodule Emisint.Assessments.MdeEnrollmentImporter do
  @batch_size 500

  @moduledoc """
  Imports MDE public student enrollment CSV data into the `mde_enrollment_results` table.

  Enrollment files are published annually by CEPI and contain building-, district-,
  and ISD-level counts broken out by race/ethnicity, grade, and subgroup.

  Unlike the assessment importer, rollup rows are detected by **blank fields** rather
  than the "0" sentinel: a blank `DistrictCode` signals an ISD-level aggregate row,
  and a blank `BuildingCode` (with a present `DistrictCode`) signals a district-level row.

  ## Pipeline

    1. **First pass** — stream the CSV to collect unique ISDs, districts, and buildings.
       Rollup rows are skipped when collecting lower-level dimensions (no phantom records).
    2. **Upsert dimension tables** in FK order:
       `MdeIsd → MdeDistrict → MdeBuilding`
       After each upsert, build a `code → UUID` lookup map.
    3. **Second pass** — stream fact rows in batches of #{@batch_size}, tag each as
       `:building`, `:district`, or `:isd`, resolve UUIDs, and bulk-upsert
       `MdeEnrollmentResult` via the appropriate action.

  ## Expected CSV column headers

      SchoolYear, ISDCode, ISDName, DistrictCode, DistrictName,
      BuildingCode, BuildingName, CountyCode, CountyName, EntityType,
      SchoolLevel, LOCALE_NAME, MISTEM_NAME, MISTEM_CODE,
      Total, Male, Female,
      AmericanIndian, Asian, AfricanAmerican, Hispanic, Hawaiian, White, TwoOrMoreRaces,
      EarlyMiddleCollege, PreKindergarten, Kindergarten,
      Grade1 … Grade12, Ungraded,
      EconomicallyDisadvantaged, SpecialEducation, EnglishLanguageLearners

  ## Usage

      iex> Emisint.Assessments.MdeEnrollmentImporter.import_file("priv/data/enrollment_2024.csv")
      {:ok, %{records: 4123, errors: 0, school_year: "2023-2024"}}

  """

  alias Emisint.Assessments.{MdeBuilding, MdeDistrict, MdeEnrollmentResult, MdeIsd}

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

      {record_count, error_count} = upsert_results(path, building_map, district_map, isd_map)

      {:ok,
       %{
         records: record_count,
         errors: error_count,
         school_year: school_year
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
      district_code = nilify(row["DistrictCode"])
      building_code = nilify(row["BuildingCode"])

      school_year = school_year || nilify(row["SchoolYear"])

      # ISDs are always real — every row belongs to an ISD
      isds =
        Map.put_new(isds, isd_code, %{
          isd_code: isd_code,
          isd_name: row["ISDName"]
        })

      # district_code nil means ISD-level rollup — skip, no real district
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

      # building_code nil means district or ISD rollup — skip, no real building
      buildings =
        if district_code == nil || building_code == nil do
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

  # Tags one row as {:building, attrs}, {:district, attrs}, {:isd, attrs}, or nil.
  # Routing logic (blank = rollup, unlike assessment CSV which uses "0"):
  #   district_code blank → ISD-level aggregate
  #   building_code blank (district present) → district-level aggregate
  #   otherwise → building-level row
  defp tag_row(row, building_map, district_map, isd_map) do
    district_code = nilify(row["DistrictCode"])
    building_code = nilify(row["BuildingCode"])
    isd_code = row["ISDCode"]
    base = to_enrollment_attrs(row)

    cond do
      district_code == nil ->
        mde_isd_id = Map.get(isd_map, isd_code)

        if is_nil(mde_isd_id),
          do: nil,
          else: {:isd, Map.merge(base, %{mde_isd_id: mde_isd_id, rollup_level: :isd})}

      building_code == nil ->
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

  # Extracts dimension strings + enrollment counts from a CSV row (no FK resolution).
  defp to_enrollment_attrs(row) do
    %{
      school_year: nilify(row["SchoolYear"]),
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
      locale_name: nilify(row["LOCALE_NAME"]),
      mistem_name: nilify(row["MISTEM_NAME"]),
      mistem_code: nilify(row["MISTEM_CODE"]),
      total_enrollment: parse_integer(row["Total"]),
      male_enrollment: parse_integer(row["Male"]),
      female_enrollment: parse_integer(row["Female"]),
      american_indian_enrollment: parse_integer(row["AmericanIndian"]),
      asian_enrollment: parse_integer(row["Asian"]),
      african_american_enrollment: parse_integer(row["AfricanAmerican"]),
      hispanic_enrollment: parse_integer(row["Hispanic"]),
      hawaiian_enrollment: parse_integer(row["Hawaiian"]),
      white_enrollment: parse_integer(row["White"]),
      two_or_more_races_enrollment: parse_integer(row["TwoOrMoreRaces"]),
      early_middle_college_enrollment: parse_integer(row["EarlyMiddleCollege"]),
      prekindergarten_enrollment: parse_integer(row["PreKindergarten"]),
      kindergarten_enrollment: parse_integer(row["Kindergarten"]),
      grade_1_enrollment: parse_integer(row["Grade1"]),
      grade_2_enrollment: parse_integer(row["Grade2"]),
      grade_3_enrollment: parse_integer(row["Grade3"]),
      grade_4_enrollment: parse_integer(row["Grade4"]),
      grade_5_enrollment: parse_integer(row["Grade5"]),
      grade_6_enrollment: parse_integer(row["Grade6"]),
      grade_7_enrollment: parse_integer(row["Grade7"]),
      grade_8_enrollment: parse_integer(row["Grade8"]),
      grade_9_enrollment: parse_integer(row["Grade9"]),
      grade_10_enrollment: parse_integer(row["Grade10"]),
      grade_11_enrollment: parse_integer(row["Grade11"]),
      grade_12_enrollment: parse_integer(row["Grade12"]),
      ungraded_enrollment: parse_integer(row["Ungraded"]),
      economic_disadvantaged_enrollment: parse_integer(row["EconomicallyDisadvantaged"]),
      special_education_enrollment: parse_integer(row["SpecialEducation"]),
      english_language_learners_enrollment: parse_integer(row["EnglishLanguageLearners"])
    }
  end

  # ---------------------------------------------------------------------------
  # Bulk upsert helper
  # ---------------------------------------------------------------------------

  defp bulk_upsert([], _action), do: %{error_count: 0}

  defp bulk_upsert(rows, action) do
    Ash.bulk_create(rows, MdeEnrollmentResult, action,
      authorize?: false,
      return_errors?: true
    )
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
  # Value coercion helpers
  # ---------------------------------------------------------------------------

  defp validate_file(path) do
    if File.exists?(path),
      do: :ok,
      else: {:error, "File not found: #{path}"}
  end

  # Empty string and whitespace-only values → nil
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
end
