defmodule Emisint.Assessments.MdeImportLog do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "mde_import_logs"
    repo Emisint.Repo

    custom_indexes do
      index [:import_type, :inserted_at]
      index [:status, :inserted_at]
      index [:uploaded_by_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :import_type,
        :original_filename,
        :file_size_bytes,
        :s3_key,
        :status,
        :school_year,
        :uploaded_by_id
      ]
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :status,
        :records_processed,
        :error_count,
        :error_message,
        :school_year,
        :metadata
      ]
    end

    update :mark_processing do
      require_atomic? false
      change set_attribute(:status, :processing)
    end

    update :mark_completed do
      require_atomic? false

      accept [:records_processed, :error_count, :school_year, :metadata]

      change set_attribute(:status, :completed)
    end

    update :mark_failed do
      require_atomic? false

      accept [:error_message]

      change set_attribute(:status, :failed)
    end

    read :list_recent do
      argument :limit, :integer, default: 50
      prepare build(sort: [inserted_at: :desc], limit: arg(:limit))
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

    attribute :import_type, :atom do
      constraints one_of: [:mde, :entity_master, :enrollment, :sat, :school_index, :emo_contact]
      allow_nil? false
      public? true
    end

    attribute :original_filename, :string do
      allow_nil? false
      public? true
    end

    attribute :file_size_bytes, :integer do
      allow_nil? true
      public? true
    end

    attribute :s3_key, :string do
      allow_nil? true
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:uploading, :processing, :completed, :failed]
      default :uploading
      allow_nil? false
      public? true
    end

    attribute :records_processed, :integer do
      allow_nil? true
      public? true
    end

    attribute :error_count, :integer do
      allow_nil? true
      public? true
    end

    attribute :error_message, :string do
      allow_nil? true
      public? true
    end

    attribute :school_year, :string do
      allow_nil? true
      public? true
    end

    attribute :metadata, :map do
      allow_nil? true
      public? true
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :uploaded_by, Emisint.Accounts.User do
      allow_nil? true
      attribute_writable? true
      public? true
    end
  end
end
