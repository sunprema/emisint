defmodule Emisint.Registry.AcademicYear do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Registry,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "academic_years"
    repo Emisint.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :label,
        :start_date,
        :end_date,
        :fall_window_start,
        :fall_window_end,
        :winter_window_start,
        :winter_window_end,
        :spring_window_start,
        :spring_window_end,
        :active
      ]
    end

    update :update do
      primary? true

      accept [
        :label,
        :start_date,
        :end_date,
        :fall_window_start,
        :fall_window_end,
        :winter_window_start,
        :winter_window_end,
        :spring_window_start,
        :spring_window_end,
        :active
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

    attribute :label, :string do
      allow_nil? false
      public? true
    end

    attribute :start_date, :date do
      allow_nil? false
      public? true
    end

    attribute :end_date, :date do
      allow_nil? false
      public? true
    end

    attribute :fall_window_start, :date do
      public? true
    end

    attribute :fall_window_end, :date do
      public? true
    end

    attribute :winter_window_start, :date do
      public? true
    end

    attribute :winter_window_end, :date do
      public? true
    end

    attribute :spring_window_start, :date do
      public? true
    end

    attribute :spring_window_end, :date do
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

  relationships do
    has_many :enrollments, Emisint.Registry.Enrollment do
      public? true
    end
  end

  identities do
    identity :unique_label_per_org, [:label, :organization_id]
  end
end
