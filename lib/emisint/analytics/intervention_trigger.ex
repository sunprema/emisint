defmodule Emisint.Analytics.InterventionTrigger do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Analytics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine]

  postgres do
    table "intervention_triggers"
    repo Emisint.Repo

    custom_indexes do
      index [:organization_id, :status]
      index [:school_id, :academic_year_id, :status]
      index [:school_id, :trigger_type, :status]
    end
  end

  state_machine do
    initial_states [:active]
    default_initial_state :active
    state_attribute :status

    transitions do
      transition :resolve, from: :active, to: :resolved
      transition :dismiss, from: :active, to: :dismissed
      transition :reactivate, from: [:resolved, :dismissed], to: :active
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :trigger_type,
        :severity,
        :triggered_at,
        :notes,
        :school_id,
        :academic_year_id,
        :schedule71_goal_id
      ]
    end

    update :resolve do
      accept [:notes, :resolved_at]
      change transition_state(:resolved)
    end

    update :dismiss do
      accept [:notes]
      change transition_state(:dismissed)
    end

    update :reactivate do
      accept []
      change transition_state(:active)
    end

    update :update do
      primary? true
      accept [:notes, :severity]
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

    attribute :trigger_type, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :proficiency_declining,
                    :sgp_below_target,
                    :growth_at_risk,
                    :goal_at_risk
                  ]
    end

    attribute :severity, :atom do
      allow_nil? false
      default :medium
      public? true
      constraints one_of: [:high, :medium, :low]
    end

    attribute :triggered_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    # Resolution notes — set when resolving or dismissing
    attribute :notes, :string do
      public? true
    end

    attribute :resolved_at, :utc_datetime_usec do
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
    belongs_to :school, Emisint.Accounts.School do
      allow_nil? false
      attribute_writable? true
      public? true
    end

    belongs_to :academic_year, Emisint.Registry.AcademicYear do
      allow_nil? false
      attribute_writable? true
      public? true
    end

    belongs_to :schedule71_goal, Emisint.Compliance.Schedule71Goal do
      allow_nil? true
      attribute_writable? true
      public? true
    end
  end
end
