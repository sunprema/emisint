defmodule Emisint.Assessments.BenchmarkProvider do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "benchmark_providers"
    repo Emisint.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :code, :scoring_system, :subjects]
    end

    update :update do
      primary? true
      accept [:name, :subjects]
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

    attribute :code, :string do
      allow_nil? false
      public? true
    end

    attribute :scoring_system, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:nwea_map, :i_ready, :other]
    end

    attribute :subjects, {:array, :string} do
      allow_nil? false
      default []
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
    identity :unique_code_per_org, [:code, :organization_id]
  end
end
