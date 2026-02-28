defmodule Emisint.Compliance.CharterContract do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Compliance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshPaperTrail.Resource]

  postgres do
    table "charter_contracts"
    repo Emisint.Repo

    custom_indexes do
      index [:organization_id, :school_id]
      index [:organization_id, :status]
    end
  end

  paper_trail do
    change_tracking_mode(:changes_only)
    store_action_name?(true)
    attributes_as_attributes([:organization_id])
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :authorizer_name,
        :contract_start_date,
        :contract_end_date,
        :reauthorization_date,
        :status,
        :school_id
      ]
    end

    update :update do
      primary? true

      accept [
        :authorizer_name,
        :contract_start_date,
        :contract_end_date,
        :reauthorization_date,
        :status
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
      authorize_if actor_attribute_equals(:role, :emo_admin)
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_primary_key :id

    attribute :authorizer_name, :string do
      allow_nil? false
      public? true
    end

    attribute :contract_start_date, :date do
      allow_nil? false
      public? true
    end

    attribute :contract_end_date, :date do
      allow_nil? false
      public? true
    end

    attribute :reauthorization_date, :date do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :expired, :under_review, :reauthorized]
    end

    attribute :organization_id, :uuid do
      allow_nil? false
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :school, Emisint.Accounts.School do
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end
end
