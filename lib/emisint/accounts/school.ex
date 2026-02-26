defmodule Emisint.Accounts.School do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "schools"
    repo Emisint.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :mde_district_code, :mde_building_code, :city, :county, :active]
    end

    update :update do
      primary? true
      accept [:name, :city, :county, :active]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system_admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if actor_attribute_equals(:organization_id, :organization_id)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :emo_admin)
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :mde_district_code, :string do
      allow_nil? false
      public? true
    end

    attribute :mde_building_code, :string do
      allow_nil? false
      public? true
    end

    attribute :city, :string do
      public? true
    end

    attribute :county, :string do
      public? true
    end

    attribute :active, :boolean do
      default true
      public? true
    end

    attribute :organization_id, :uuid do
      allow_nil? false
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_building_code_per_org, [:mde_building_code, :organization_id]
  end
end
