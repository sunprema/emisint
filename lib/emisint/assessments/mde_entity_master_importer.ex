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
      {:ok, %{records: 4200, errors: 0, error_file: nil}}

  """

  alias Emisint.Assessments.MdeEntityMaster

  # ---------------------------------------------------------------------------
  # CSV column → atom field mapping (61 columns)
  # ---------------------------------------------------------------------------

  @header_map %{
    "ISDCode" => :isd_code,
    "ISDOfficialName" => :isd_official_name,
    "DistrictCode" => :district_code,
    "DistrictOfficialName" => :district_official_name,
    "DistrictType" => :district_type,
    "DistrictTypeName" => :district_type_name,
    "DistrictCommonName" => :district_common_name,
    "EntityCode" => :entity_code,
    "EntityOfficialName" => :entity_official_name,
    "AgreementNumber" => :agreement_number,
    "EntityType" => :entity_type,
    "EntityTypeName" => :entity_type_name,
    "EntityTypeGroup" => :entity_type_group,
    "EntityTypeGroupName" => :entity_type_group_name,
    "EntityTypeCategory" => :entity_type_category,
    "EntityTypeCategoryName" => :entity_type_category_name,
    "EntityCountyCode" => :entity_county_code,
    "EntityCountyName" => :entity_county_name,
    "EntityCharteringAgencyCode" => :entity_chartering_agency_code,
    "EntityCharteringAgencyName" => :entity_chartering_agency_name,
    "EntityGeographicLEADistrictCode" => :entity_geographic_lea_district_code,
    "EntityGeographicLEADistrictOfficialName" => :entity_geographic_lea_district_official_name,
    "EntityNCESCode" => :entity_nces_code,
    "EntityLocaleCode" => :entity_locale_code,
    "EntityLocaleName" => :entity_locale_name,
    "EntityAuthorizedEducationalSettings" => :entity_authorized_educational_settings,
    "EntityActualEducationalSettings" => :entity_actual_educational_settings,
    "EntityStatus" => :entity_status,
    "EntityOpenDate" => :entity_open_date,
    "EntityCloseDate" => :entity_close_date,
    "EntityAuthorizedGrades" => :entity_authorized_grades,
    "EntityActualGrades" => :entity_actual_grades,
    "EntityFIPSCode" => :entity_fips_code,
    # MDE source file has a typo: "Enttiy" (double-t) — match it exactly.
    "EnttiyREMCId" => :entity_remc_id,
    "EntityScheduleList" => :entity_schedules_list,
    "EntityEarlyChildhoodProgramList" => :entity_early_childhood_program_list,
    "ReceivesTransportationServicesFromCode" => :receives_transportation_from_code,
    "ReceivesTransportationServicesFromOfficialName" => :receives_transportation_from_name,
    "EntityReligiousOrientationCode" => :entity_religious_orientation_code,
    "EntityReligiousOrientationName" => :entity_religious_orientation_name,
    "EntityEmail" => :entity_email,
    "EntityPhone" => :entity_phone,
    "EntityPhoneExt" => :entity_phone_ext,
    "EntityFax" => :entity_fax,
    "EntityFaxExt" => :entity_fax_ext,
    "EntityLeadAdminHonorific" => :entity_lead_admin_honorific,
    "EntityLeadAdminFirstName" => :entity_lead_admin_first_name,
    "EntityLeadAdminLastName" => :entity_lead_admin_last_name,
    "EntityPhysicalStreet" => :entity_physical_street,
    "EntityPhysicalCity" => :entity_physical_city,
    "EntityPhysicalState" => :entity_physical_state,
    "EntityPhysicalZip4" => :entity_physical_zip4,
    "EntityMailingStreet" => :entity_mailing_street,
    "EntityMailingCity" => :entity_mailing_city,
    "EntityMailingState" => :entity_mailing_state,
    "EntityMailingZip4" => :entity_mailing_zip4,
    "EarlyMiddleCollege" => :early_middle_college,
    "SEEType" => :see_type,
    "HeadStartGrantee" => :head_start_grantee,
    "SchoolEmphasis" => :school_emphasis,
    "ESSASupportStatus" => :essa_support_category_status
  }

  @upsert_fields [
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

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Bulk upsert
  # ---------------------------------------------------------------------------

  defp bulk_upsert([]), do: {0, 0, []}

  defp bulk_upsert(rows) do
    result =
      Ash.bulk_create(rows, MdeEntityMaster, :upsert,
        authorize?: false,
        return_errors?: true,
        upsert_fields: @upsert_fields
      )

    error_rows =
      if result.error_count > 0 do
        Enum.filter(rows, fn row ->
          r =
            Ash.bulk_create([row], MdeEntityMaster, :upsert,
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

  defp to_attrs(row) do
    attrs =
      Enum.reduce(@header_map, %{}, fn {csv_col, field}, acc ->
        val = Map.get(row, csv_col)
        Map.put(acc, field, nilify(val))
      end)

    attrs =
      attrs
      |> Map.update(:entity_code, nil, &normalize_entity_code/1)
      |> Map.update(:isd_code, nil, &normalize_entity_code/1)
      |> Map.update(:district_code, nil, &normalize_entity_code/1)
      |> Map.update(:entity_geographic_lea_district_code, nil, &normalize_entity_code/1)

    if is_nil(attrs[:entity_code]), do: nil, else: attrs
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

  defp normalize_entity_code(nil), do: nil

  defp normalize_entity_code(code) do
    case String.trim_leading(code, "0") do
      "" -> "0"
      stripped -> stripped
    end
  end
end
