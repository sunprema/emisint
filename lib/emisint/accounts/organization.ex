defmodule Emisint.Accounts.Organization do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "organizations"
    repo Emisint.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :type, :slug]
    end

    update :update do
      primary? true
      accept [:name, :active, :primary_contact_name, :primary_contact_phone, :primary_contact_email]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_slug
      accept [:name, :type, :slug, :mde_district_code, :primary_contact_name, :primary_contact_phone, :primary_contact_email]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system_admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(id == ^actor(:organization_id))
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :emo_admin)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:emo, :authorizer, :admin, :self_managed]
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
    end

    attribute :active, :boolean do
      default true
      public? true
    end

    attribute :mde_district_code, :string do
      public? true
    end

    attribute :primary_contact_name, :string do
      public? true
    end

    attribute :primary_contact_phone, :string do
      public? true
    end

    attribute :primary_contact_email, :string do
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
