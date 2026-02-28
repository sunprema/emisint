defmodule Emisint.Assessments.MdeEntityMasterImporter do
  @batch_size 500

  @moduledoc """
  Imports the MDE EntityMaster daily CSV into `mde_entity_masters`.

  The EntityMaster file contains the complete registry of Michigan school
  entities (~61 columns). Every row is upserted on `entity_code` so repeated
  imports are idempotent.

  ## Pipeline

    1. Validate the file exists.
    2. Stream the CSV as string-keyed maps (handles optional UTF-8 BOM).
    3. Map each row to `MdeEntityMaster` attrs via `@header_map`.
    4. Bulk-upsert in batches of #{@batch_size}.

  ## Usage

      iex> Emisint.Assessments.MdeEntityMasterImporter.import_file("/tmp/EntityMaster.csv")
      {:ok, %{records: 4200, errors: 0}}

  """

  alias Emisint.Assessments.MdeEntityMaster

  # ---------------------------------------------------------------------------
  # CSV column → atom field mapping (61 columns)
  # ---------------------------------------------------------------------------

  @header_map %{
    "ISD Code" => :isd_code,
    "ISD Official Name" => :isd_official_name,
    "District Code" => :district_code,
    "District Official Name" => :district_official_name,
    "District Type" => :district_type,
    "District Type Name" => :district_type_name,
    "District Common Name" => :district_common_name,
    "Entity Code" => :entity_code,
    "Entity Official Name" => :entity_official_name,
    "Agreement Number" => :agreement_number,
    "Entity Type" => :entity_type,
    "Entity Type Name" => :entity_type_name,
    "Entity Type Group" => :entity_type_group,
    "Entity Type Group Name" => :entity_type_group_name,
    "Entity Type Category" => :entity_type_category,
    "Entity Type Category Name" => :entity_type_category_name,
    "Entity County Code" => :entity_county_code,
    "Entity County Name" => :entity_county_name,
    "Entity Chartering Agency Code" => :entity_chartering_agency_code,
    "Entity Chartering Agency Name" => :entity_chartering_agency_name,
    "Entity Geographic LEA District Code" => :entity_geographic_lea_district_code,
    "Entity Geographic LEA District Official Name" =>
      :entity_geographic_lea_district_official_name,
    "Entity NCES Code" => :entity_nces_code,
    "Entity Locale Code" => :entity_locale_code,
    "Entity Locale Name" => :entity_locale_name,
    "Entity Authorized Educational Settings" => :entity_authorized_educational_settings,
    "Entity Actual Educational Settings" => :entity_actual_educational_settings,
    "Entity Status" => :entity_status,
    "Entity Open Date" => :entity_open_date,
    "Entity Close Date" => :entity_close_date,
    "Entity Authorized Grades" => :entity_authorized_grades,
    "Entity Actual Grades" => :entity_actual_grades,
    "Entity FIPS Code" => :entity_fips_code,
    "Entity REMC Id" => :entity_remc_id,
    "Entity Schedules List" => :entity_schedules_list,
    "Entity Early Childhood Program List" => :entity_early_childhood_program_list,
    "Receives Transportation Services From Code" => :receives_transportation_from_code,
    "Receives Transportation Services From Official Name" => :receives_transportation_from_name,
    "Entity Religious Orientation Code" => :entity_religious_orientation_code,
    "Entity Religious Orientation Name" => :entity_religious_orientation_name,
    "Entity Email" => :entity_email,
    "Entity Phone" => :entity_phone,
    "Entity Phone Ext" => :entity_phone_ext,
    "Entity Fax" => :entity_fax,
    "Entity Fax Ext" => :entity_fax_ext,
    "Entity Lead Admin Honorific" => :entity_lead_admin_honorific,
    "Entity Lead Admin First Name" => :entity_lead_admin_first_name,
    "Entity Lead Admin Last Name" => :entity_lead_admin_last_name,
    "Entity Physical Street" => :entity_physical_street,
    "Entity Physical City" => :entity_physical_city,
    "Entity Physical State" => :entity_physical_state,
    "Entity Physical Zip4" => :entity_physical_zip4,
    "Entity Mailing Street" => :entity_mailing_street,
    "Entity Mailing City" => :entity_mailing_city,
    "Entity Mailing State" => :entity_mailing_state,
    "Entity Mailing Zip4" => :entity_mailing_zip4,
    "Early Middle College" => :early_middle_college,
    "SEEType" => :see_type,
    "Head Start Grantee" => :head_start_grantee,
    "School Emphasis" => :school_emphasis,
    "ESSA Support Category Status" => :essa_support_category_status
  }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec import_file(Path.t()) :: {:ok, map()} | {:error, String.t()}
  def import_file(path) do
    with :ok <- validate_file(path) do
      {record_count, error_count} =
        stream_as_maps(path)
        |> Stream.map(&to_attrs/1)
        |> Stream.reject(&is_nil/1)
        |> Stream.chunk_every(@batch_size)
        |> Enum.reduce({0, 0}, fn batch, {ok_acc, err_acc} ->
          result =
            Ash.bulk_create(batch, MdeEntityMaster, :upsert,
              authorize?: false,
              return_errors?: true,
              upsert_fields: [
                :isd_code,
                :isd_official_name,
                :district_code,
                :district_official_name,
                :district_type,
                :district_type_name,
                :district_common_name,
                :entity_official_name,
                :agreement_number,
                :entity_type,
                :entity_type_name,
                :entity_type_group,
                :entity_type_group_name,
                :entity_type_category,
                :entity_type_category_name,
                :entity_county_code,
                :entity_county_name,
                :entity_chartering_agency_code,
                :entity_chartering_agency_name,
                :entity_geographic_lea_district_code,
                :entity_geographic_lea_district_official_name,
                :entity_nces_code,
                :entity_locale_code,
                :entity_locale_name,
                :entity_authorized_educational_settings,
                :entity_actual_educational_settings,
                :entity_status,
                :entity_open_date,
                :entity_close_date,
                :entity_authorized_grades,
                :entity_actual_grades,
                :entity_fips_code,
                :entity_remc_id,
                :entity_schedules_list,
                :entity_early_childhood_program_list,
                :receives_transportation_from_code,
                :receives_transportation_from_name,
                :entity_religious_orientation_code,
                :entity_religious_orientation_name,
                :entity_email,
                :entity_phone,
                :entity_phone_ext,
                :entity_fax,
                :entity_fax_ext,
                :entity_lead_admin_honorific,
                :entity_lead_admin_first_name,
                :entity_lead_admin_last_name,
                :entity_physical_street,
                :entity_physical_city,
                :entity_physical_state,
                :entity_physical_zip4,
                :entity_mailing_street,
                :entity_mailing_city,
                :entity_mailing_state,
                :entity_mailing_zip4,
                :early_middle_college,
                :see_type,
                :head_start_grantee,
                :school_emphasis,
                :essa_support_category_status
              ]
            )

          batch_ok = length(batch) - result.error_count
          {ok_acc + batch_ok, err_acc + result.error_count}
        end)

      {:ok, %{records: record_count, errors: error_count}}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  # ---------------------------------------------------------------------------
  # Streaming helpers
  # ---------------------------------------------------------------------------

  # Streams the CSV as string-keyed maps, one per data row.
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

  # Maps one CSV row-map to MdeEntityMaster attrs using @header_map.
  # Returns nil when entity_code is missing or blank (skip the row).
  defp to_attrs(row) do
    attrs =
      Enum.reduce(@header_map, %{}, fn {csv_col, field}, acc ->
        val = Map.get(row, csv_col)
        Map.put(acc, field, nilify(val))
      end)

    if is_nil(attrs[:entity_code]), do: nil, else: attrs
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
end
