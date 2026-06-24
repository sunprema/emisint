defmodule Emisint.Assessments.MdeCompositeResidentDistrictImporter do
  @batch_size 200

  @moduledoc """
  Imports the MDE **Composite Resident District (CRD)** CSV into
  `mde_composite_resident_districts`.

  Every row is upserted on `(school_year, charter_district_code, crd_district_code)`
  so repeated imports are idempotent.

  ## Pipeline

    1. Validate the file exists.
    2. Build a normalized-name → `MdeDistrict.id` map (for resolving the resident
       district — the CRD code is unreliable, see below).
    3. Stream the CSV as string-keyed maps (handles optional UTF-8 BOM).
    4. Map each row to attrs via `@header_map`, normalizing the charter district
       code, parsing the integer count, and resolving `mde_district_id` by name.
    5. Bulk-upsert in batches of #{@batch_size}.

  ## District code caveat

  `charter_district_code` (CSV "District Code") is a real MDE code → leading zeros
  are stripped so it joins to `MdeDistrict`. `crd_district_code` (CSV "CRD District
  Code") does NOT correspond to MDE district codes — it is stored raw and is part
  of the natural key only. The resident district is resolved to `MdeDistrict` by
  the normalized `resident_entity_name`; rows with no name match get
  `mde_district_id = nil` (and are counted as `unmatched`) but are still imported.

  ## Expected CSV columns

      School Year, Entity Name, District Code, Other Entity Name,
      CRD District Code, Grade, Number of Nonresident Students Enrolled

  ## Usage

      iex> Emisint.Assessments.MdeCompositeResidentDistrictImporter.import_file("/tmp/crd.csv")
      {:ok, %{records: 27, errors: 0, matched: 27, unmatched: 0, error_file: nil}}

  """

  require Ash.Query

  alias Emisint.Assessments.MdeCompositeResidentDistrict
  alias Emisint.Assessments.MdeDistrict

  @header_map %{
    "School Year" => :school_year,
    "Entity Name" => :charter_entity_name,
    "District Code" => :charter_district_code,
    "Other Entity Name" => :resident_entity_name,
    "CRD District Code" => :crd_district_code,
    "Grade" => :grade,
    "Number of Nonresident Students Enrolled" => :nonresident_students_enrolled
  }

  @upsert_fields [
    :charter_entity_name,
    :resident_entity_name,
    :grade,
    :nonresident_students_enrolled,
    :mde_district_id
  ]

  @spec import_file(Path.t()) :: {:ok, map()} | {:error, String.t()}
  def import_file(path) do
    with :ok <- validate_file(path) do
      name_map = build_district_name_map()

      {record_count, error_count, matched, unmatched, error_rows} =
        stream_as_maps(path)
        |> Stream.map(&to_attrs(&1, name_map))
        |> Stream.reject(&is_nil/1)
        |> Stream.chunk_every(@batch_size)
        |> Enum.reduce({0, 0, 0, 0, []}, fn batch,
                                            {ok_acc, err_acc, m_acc, u_acc, err_rows_acc} ->
          {batch_ok, batch_err, batch_err_rows} = bulk_upsert(batch)
          {batch_m, batch_u} = count_matches(batch)

          {ok_acc + batch_ok, err_acc + batch_err, m_acc + batch_m, u_acc + batch_u,
           err_rows_acc ++ batch_err_rows}
        end)

      error_file = write_error_csv(path, error_rows)

      {:ok,
       %{
         records: record_count,
         errors: error_count,
         matched: matched,
         unmatched: unmatched,
         error_file: error_file
       }}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp count_matches(batch) do
    Enum.reduce(batch, {0, 0}, fn attrs, {m, u} ->
      if attrs[:mde_district_id], do: {m + 1, u}, else: {m, u + 1}
    end)
  end

  defp bulk_upsert([]), do: {0, 0, []}

  defp bulk_upsert(rows) do
    result =
      Ash.bulk_create(rows, MdeCompositeResidentDistrict, :upsert,
        authorize?: false,
        return_errors?: true,
        upsert_fields: @upsert_fields
      )

    error_rows =
      if result.error_count > 0 do
        Enum.filter(rows, fn row ->
          r =
            Ash.bulk_create([row], MdeCompositeResidentDistrict, :upsert,
              authorize?: false,
              return_errors?: true,
              upsert_fields: @upsert_fields
            )

          r.error_count > 0
        end)
      else
        []
      end

    {length(rows) - result.error_count, result.error_count, error_rows}
  end

  defp build_district_name_map do
    MdeDistrict
    |> Ash.read!(authorize?: false)
    |> Enum.reduce(%{}, fn d, acc ->
      Map.put(acc, normalize_name(d.district_name), d.id)
    end)
  end

  defp stream_as_maps(path) do
    File.stream!(path)
    |> NimbleCSV.RFC4180.parse_stream(skip_headers: false)
    |> Stream.transform(nil, fn
      [first | rest], nil ->
        headers = [String.trim_leading(first, "﻿") | rest]
        headers = Enum.map(headers, &String.trim/1)
        {[], headers}

      row, headers ->
        row_map = headers |> Enum.zip(row) |> Map.new()
        {[row_map], headers}
    end)
  end

  defp to_attrs(row, name_map) do
    attrs =
      Enum.reduce(@header_map, %{}, fn {csv_col, field}, acc ->
        val = Map.get(row, csv_col) || Map.get(row, String.trim(csv_col))
        Map.put(acc, field, nilify(val))
      end)

    attrs =
      attrs
      |> Map.update(:charter_district_code, nil, &normalize_district_code/1)
      |> Map.update(:crd_district_code, nil, &nilify/1)
      |> Map.update(:nonresident_students_enrolled, nil, &parse_integer/1)
      |> Map.put(:mde_district_id, resolve_district_id(attrs[:resident_entity_name], name_map))

    if key_present?(attrs), do: attrs, else: nil
  end

  defp key_present?(attrs) do
    not is_nil(attrs[:school_year]) and not is_nil(attrs[:charter_district_code]) and
      not is_nil(attrs[:crd_district_code])
  end

  defp resolve_district_id(nil, _name_map), do: nil
  defp resolve_district_id(name, name_map), do: Map.get(name_map, normalize_name(name))

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

  defp parse_integer(nil), do: nil

  defp parse_integer(val) when is_binary(val) do
    case val |> String.trim() |> String.replace(",", "") |> Integer.parse() do
      {int, _rest} -> int
      :error -> nil
    end
  end

  defp parse_integer(val) when is_integer(val), do: val

  # MDE district codes are stored with leading zeros stripped across the codebase.
  defp normalize_district_code(nil), do: nil

  defp normalize_district_code(code) do
    case String.trim_leading(String.trim(code), "0") do
      "" -> "0"
      stripped -> stripped
    end
  end

  defp normalize_name(nil), do: nil

  defp normalize_name(name) do
    name
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
