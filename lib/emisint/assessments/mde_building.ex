defmodule Emisint.Assessments.MdeBuilding do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "mde_buildings"
    repo Emisint.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :building_code,
        :building_name,
        :school_level,
        :locale,
        :mistem_name,
        :mistem_code,
        :mde_district_id
      ]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_building_code

      upsert_fields [
        :building_name,
        :school_level,
        :locale,
        :mistem_name,
        :mistem_code,
        :mde_district_id
      ]

      accept [
        :building_code,
        :building_name,
        :school_level,
        :locale,
        :mistem_name,
        :mistem_code,
        :mde_district_id
      ]
    end

    update :update do
      primary? true

      accept [
        :building_name,
        :school_level,
        :locale,
        :mistem_name,
        :mistem_code,
        :mde_district_id
      ]
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

    # MDE building code — joins to School.mde_building_code for tenant-scoped schools
    attribute :building_code, :string do
      allow_nil? false
      public? true
    end

    attribute :building_name, :string do
      allow_nil? false
      public? true
    end

    # e.g. "Elementary", "Middle", "High", "K-12"
    attribute :school_level, :string do
      public? true
    end

    # MDE locale classification: "City", "Suburb", "Town", "Rural"
    attribute :locale, :string do
      public? true
    end

    # Michigan STEM designation — null for non-designated buildings
    attribute :mistem_name, :string do
      public? true
    end

    attribute :mistem_code, :string do
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :mde_district, Emisint.Assessments.MdeDistrict do
      allow_nil? true
      attribute_writable? true
      public? true
    end
  end

  identities do
    identity :unique_building_code, [:building_code]
  end
end
