defmodule Emisint.Analytics.DataSyncLog do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Analytics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "data_sync_logs"
    repo Emisint.Repo

    custom_indexes do
      index [:organization_id, :job_type]
      index [:organization_id, :created_at]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:job_type, :metadata]
    end

    # Marks job as running; caller supplies started_at timestamp
    update :start do
      accept [:started_at]
      change set_attribute(:status, :running)
    end

    # Marks job as completed with result counts
    update :complete do
      accept [:records_processed, :records_failed, :completed_at]
      change set_attribute(:status, :completed)
    end

    # Marks job as failed with error details
    update :fail do
      accept [:error_message, :completed_at]
      change set_attribute(:status, :failed)
    end

    update :update do
      primary? true
      accept [:records_processed, :records_failed, :error_message, :metadata]
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

    attribute :job_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:csv_import, :snapshot_refresh, :goal_recalculation, :mde_sync]
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :running, :completed, :failed]
    end

    attribute :records_processed, :integer do
      public? true
    end

    attribute :records_failed, :integer do
      public? true
    end

    attribute :error_message, :string do
      public? true
    end

    attribute :started_at, :utc_datetime_usec do
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      public? true
    end

    # Arbitrary extra context: filename, school_id, provider_code, etc.
    attribute :metadata, :map do
      default %{}
      public? true
    end

    attribute :organization_id, :uuid do
      allow_nil? false
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end
end
