defmodule Emisint.Assessments.MdeEmoContactImporter do
  @batch_size 200

  @moduledoc """
  Imports the MDE Open/Active EMO and Authorizer contact list CSV into
  `mde_emo_contacts`.

  Every row is upserted on `district_code` so repeated imports are idempotent.

  ## Pipeline

    1. Validate the file exists.
    2. Stream the CSV as string-keyed maps (handles optional UTF-8 BOM).
    3. Map each row to `MdeEmoContact` attrs via `@header_map`.
    4. Bulk-upsert in batches of #{@batch_size}.

  ## Expected CSV columns

      District Code, PSA Official Name, Chartering Agency,
      Education Service Provider/Management Organization, Name, Phone, E-Mail

  ## Usage

      iex> Emisint.Assessments.MdeEmoContactImporter.import_file("/tmp/emo_contacts.csv")
      {:ok, %{records: 289, errors: 0, error_file: nil}}

  """

  alias Emisint.Assessments.MdeEmoContact

  @header_map %{
    "District Code" => :district_code,
    "PSA Official Name" => :psa_official_name,
    "PSA Official Name " => :psa_official_name,
    "Chartering Agency" => :chartering_agency,
    "Education Service Provider/Management Organization" => :management_organization,
    "Name" => :contact_name,
    "Phone" => :contact_phone,
    "E-Mail" => :contact_email
  }

  @upsert_fields [
    :psa_official_name,
    :chartering_agency,
    :management_organization,
    :contact_name,
    :contact_phone,
    :contact_email
  ]

  @spec import_file(Path.t()) :: {:ok, map()} | {:error, String.t()}
  def import_file(path) do
    with :ok <- validate_file(path) do
      {record_count, error_count, error_rows} =
        stream_as_maps(path)
        |> Stream.map(&to_attrs/1)
        |> Stream.reject(&is_nil/1)
        |> Stream.chunk_every(@batch_size)
        |> Enum.reduce({0, 0, []}, fn batch, {ok_acc, err_acc, err_rows_acc} ->
          {batch_ok, batch_err, batch_err_rows} = bulk_upsert(batch)
          {ok_acc + batch_ok, err_acc + batch_err, err_rows_acc ++ batch_err_rows}
        end)

      error_file = write_error_csv(path, error_rows)

      {:ok, %{records: record_count, errors: error_count, error_file: error_file}}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp bulk_upsert([]), do: {0, 0, []}

  defp bulk_upsert(rows) do
    result =
      Ash.bulk_create(rows, MdeEmoContact, :upsert,
        authorize?: false,
        return_errors?: true,
        upsert_fields: @upsert_fields
      )

    error_rows =
      if result.error_count > 0 do
        Enum.filter(rows, fn row ->
          r =
            Ash.bulk_create([row], MdeEmoContact, :upsert,
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

  defp to_attrs(row) do
    attrs =
      Enum.reduce(@header_map, %{}, fn {csv_col, field}, acc ->
        val = Map.get(row, csv_col) || Map.get(row, String.trim(csv_col))
        Map.put(acc, field, nilify(val))
      end)

    attrs = Map.update(attrs, :district_code, nil, &normalize_district_code/1)

    if is_nil(attrs[:district_code]), do: nil, else: attrs
  end

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

  defp normalize_district_code(nil), do: nil

  defp normalize_district_code(code) do
    case String.trim_leading(String.trim(code), "0") do
      "" -> "0"
      stripped -> stripped
    end
  end
end
