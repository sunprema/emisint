defmodule Emisint.Assessments.MdeDistrict do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "mde_districts"
    repo Emisint.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:district_code, :district_name, :county_code, :county_name, :entity_type, :mde_isd_id]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_district_code
      upsert_fields [:district_name, :county_code, :county_name, :entity_type, :mde_isd_id]
      accept [:district_code, :district_name, :county_code, :county_name, :entity_type, :mde_isd_id]
    end

    update :update do
      primary? true
      accept [:district_name, :county_code, :county_name, :entity_type, :mde_isd_id]
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

    # MDE 5-digit district code — stable natural key
    attribute :district_code, :string do
      allow_nil? false
      public? true
    end

    attribute :district_name, :string do
      allow_nil? false
      public? true
    end

    attribute :county_code, :string do
      public? true
    end

    attribute :county_name, :string do
      public? true
    end

    # e.g. "Public School Academy", "Traditional Public", "High School District"
    attribute :entity_type, :string do
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :mde_isd, Emisint.Assessments.MdeIsd do
      allow_nil? true
      attribute_writable? true
      public? true
    end
  end

  identities do
    identity :unique_district_code, [:district_code]
  end
end
