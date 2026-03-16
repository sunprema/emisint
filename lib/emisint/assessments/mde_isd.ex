defmodule Emisint.Assessments.MdeIsd do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "mde_isds"
    repo Emisint.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:isd_code, :isd_name]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_isd_code
      upsert_fields [:isd_name]
      accept [:isd_code, :isd_name]
    end

    update :update do
      primary? true
      accept [:isd_name]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system_admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      # authorize_if actor_present()
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :system_admin)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :isd_code, :string do
      allow_nil? false
      public? true
    end

    attribute :isd_name, :string do
      allow_nil? false
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_isd_code, [:isd_code]
  end
end
