defmodule Emisint.Assessments.MdeCompositeResidentDistrict do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @moduledoc """
  Stores the MDE **Composite Resident District (CRD)** report — one row per
  `(school_year, charter, resident district)` recording how many nonresident
  students a charter (PSA) enrolls from each district those students would
  otherwise attend.

  This is a shared, non-multitenant reference table. The natural key is
  `(school_year, charter_district_code, crd_district_code)`.

  ## District code caveat (important)

  The charter-side `charter_district_code` IS a real MDE district code (leading
  zeros stripped on import) and joins to `Emisint.Assessments.MdeDistrict`.

  The `crd_district_code` column in the source CSV does **NOT** correspond to MDE
  district codes — it is stored raw/opaque and must never be used as a foreign
  key. The trustworthy resident-district identifier is `resident_entity_name`,
  which is resolved to `MdeDistrict` by normalized name at import time and stored
  on the nullable `mde_district_id` relationship (left `nil` when no name match).
  """

  @non_key_fields [
    :charter_entity_name,
    :resident_entity_name,
    :grade,
    :nonresident_students_enrolled,
    :mde_district_id
  ]

  postgres do
    table "mde_composite_resident_districts"
    repo Emisint.Repo

    custom_indexes do
      index [:charter_district_code]
      index [:mde_district_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:school_year, :charter_district_code, :crd_district_code | @non_key_fields]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_crd
      upsert_fields @non_key_fields
      accept [:school_year, :charter_district_code, :crd_district_code | @non_key_fields]
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

    attribute :school_year, :string do
      allow_nil? false
      public? true
    end

    # Reliable MDE district code for the charter (PSA), leading zeros stripped.
    attribute :charter_district_code, :string do
      allow_nil? false
      public? true
    end

    attribute :charter_entity_name, :string, public?: true

    # Opaque code from the CRD report — NOT an MDE district code. Part of the
    # natural key only; never used as a foreign key.
    attribute :crd_district_code, :string do
      allow_nil? false
      public? true
    end

    attribute :resident_entity_name, :string, public?: true
    attribute :grade, :string, public?: true
    attribute :nonresident_students_enrolled, :integer, public?: true

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    # Resolved by normalized name at import time; nil when no match.
    belongs_to :mde_district, Emisint.Assessments.MdeDistrict do
      allow_nil? true
      attribute_writable? true
      public? true
    end
  end

  identities do
    identity :unique_crd, [:school_year, :charter_district_code, :crd_district_code]
  end
end
