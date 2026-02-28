defmodule Emisint.Assessments.MdeEntityMaster do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @moduledoc """
  Stores the MDE EntityMaster daily reference feed — the complete registry of
  Michigan school entities (ISDs, districts, PSAs, traditional publics, etc.).

  This is a shared, non-multitenant reference table. All 61 CSV columns from
  the MDE EntityMaster export are stored as strings.

  The natural key is `entity_code` (MDE Building/Entity code). Soft-join to
  `Accounts.School.mde_building_code` in application code when needed.
  """

  postgres do
    table "mde_entity_masters"
    repo Emisint.Repo
  end

  @non_key_fields [
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

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:entity_code | @non_key_fields]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_entity_code
      upsert_fields @non_key_fields
      accept [:entity_code | @non_key_fields]
    end

    update :update do
      primary? true
      accept @non_key_fields
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system_admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :system_admin)
    end
  end

  attributes do
    uuid_primary_key :id

    # Natural key — MDE entity/building code
    attribute :entity_code, :string do
      allow_nil? false
      public? true
    end

    # ISD
    attribute :isd_code, :string, public?: true
    attribute :isd_official_name, :string, public?: true

    # District
    attribute :district_code, :string, public?: true
    attribute :district_official_name, :string, public?: true
    attribute :district_type, :string, public?: true
    attribute :district_type_name, :string, public?: true
    attribute :district_common_name, :string, public?: true

    # Entity identity
    attribute :entity_official_name, :string, public?: true
    attribute :agreement_number, :string, public?: true
    attribute :entity_type, :string, public?: true
    attribute :entity_type_name, :string, public?: true
    attribute :entity_type_group, :string, public?: true
    attribute :entity_type_group_name, :string, public?: true
    attribute :entity_type_category, :string, public?: true
    attribute :entity_type_category_name, :string, public?: true

    # Geography
    attribute :entity_county_code, :string, public?: true
    attribute :entity_county_name, :string, public?: true
    attribute :entity_chartering_agency_code, :string, public?: true
    attribute :entity_chartering_agency_name, :string, public?: true
    attribute :entity_geographic_lea_district_code, :string, public?: true
    attribute :entity_geographic_lea_district_official_name, :string, public?: true
    attribute :entity_nces_code, :string, public?: true
    attribute :entity_locale_code, :string, public?: true
    attribute :entity_locale_name, :string, public?: true
    attribute :entity_fips_code, :string, public?: true
    attribute :entity_remc_id, :string, public?: true

    # Educational settings & grades
    attribute :entity_authorized_educational_settings, :string, public?: true
    attribute :entity_actual_educational_settings, :string, public?: true
    attribute :entity_authorized_grades, :string, public?: true
    attribute :entity_actual_grades, :string, public?: true

    # Status & dates (kept as strings; MDE date format varies)
    attribute :entity_status, :string, public?: true
    attribute :entity_open_date, :string, public?: true
    attribute :entity_close_date, :string, public?: true

    # Programs & services
    attribute :entity_schedules_list, :string, public?: true
    attribute :entity_early_childhood_program_list, :string, public?: true
    attribute :receives_transportation_from_code, :string, public?: true
    attribute :receives_transportation_from_name, :string, public?: true
    attribute :entity_religious_orientation_code, :string, public?: true
    attribute :entity_religious_orientation_name, :string, public?: true

    # Contact info
    attribute :entity_email, :string, public?: true
    attribute :entity_phone, :string, public?: true
    attribute :entity_phone_ext, :string, public?: true
    attribute :entity_fax, :string, public?: true
    attribute :entity_fax_ext, :string, public?: true

    # Leadership
    attribute :entity_lead_admin_honorific, :string, public?: true
    attribute :entity_lead_admin_first_name, :string, public?: true
    attribute :entity_lead_admin_last_name, :string, public?: true

    # Physical address
    attribute :entity_physical_street, :string, public?: true
    attribute :entity_physical_city, :string, public?: true
    attribute :entity_physical_state, :string, public?: true
    attribute :entity_physical_zip4, :string, public?: true

    # Mailing address
    attribute :entity_mailing_street, :string, public?: true
    attribute :entity_mailing_city, :string, public?: true
    attribute :entity_mailing_state, :string, public?: true
    attribute :entity_mailing_zip4, :string, public?: true

    # Additional flags
    attribute :early_middle_college, :string, public?: true
    attribute :see_type, :string, public?: true
    attribute :head_start_grantee, :string, public?: true
    attribute :school_emphasis, :string, public?: true
    attribute :essa_support_category_status, :string, public?: true

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_entity_code, [:entity_code]
  end
end
