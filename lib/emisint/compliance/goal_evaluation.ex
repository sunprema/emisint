defmodule Emisint.Compliance.GoalEvaluation do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Compliance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshPaperTrail.Resource]

  postgres do
    table "goal_evaluations"
    repo Emisint.Repo
  end

  actions do
    defaults [:read, :destroy]

    # Direct create — all fields supplied by caller (used in tests and manual overrides)
    create :create do
      primary? true

      accept [
        :status,
        :actual_value,
        :target_value,
        :comparison_operator,
        :exceeds_threshold,
        :approaching_threshold,
        :data_points_count,
        :evaluated_at,
        :schedule71_goal_id,
        :academic_year_id
      ]
    end

    # Upsert that runs ComputeGoalActualValue to derive all score fields automatically
    create :recalculate do
      upsert? true
      upsert_identity :unique_goal_year_evaluation
      accept [:schedule71_goal_id, :academic_year_id]
      change Emisint.Compliance.Changes.ComputeGoalActualValue
    end

    update :update do
      primary? true
      accept [:status, :actual_value, :data_points_count, :evaluated_at]
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

    attribute :status, :atom do
      allow_nil? false
      default :insufficient_data
      public? true
      constraints one_of: [:exceeds, :meets, :approaching, :below, :insufficient_data]
    end

    attribute :actual_value, :decimal do
      public? true
    end

    # Snapshot of goal.target_value at evaluation time
    attribute :target_value, :decimal do
      public? true
    end

    # Snapshot of goal.comparison_operator at evaluation time
    attribute :comparison_operator, :atom do
      public? true
      constraints one_of: [:gte, :lte, :gt, :lt, :eq]
    end

    # Snapshot of goal.exceeds_threshold at evaluation time
    attribute :exceeds_threshold, :decimal do
      public? true
    end

    # Snapshot of goal.approaching_threshold at evaluation time
    attribute :approaching_threshold, :decimal do
      public? true
    end

    attribute :data_points_count, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :evaluated_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
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
    belongs_to :schedule71_goal, Emisint.Compliance.Schedule71Goal do
      allow_nil? false
      attribute_writable? true
      public? true
    end

    belongs_to :academic_year, Emisint.Registry.AcademicYear do
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end

  calculations do
    # Re-derives status from stored snapshot data — useful for verification / display
    calculate :derived_status, :atom, Emisint.Compliance.Calculations.EvaluateGoalStatus
  end

  identities do
    identity :unique_goal_year_evaluation, [:schedule71_goal_id, :academic_year_id]
  end

  paper_trail do
    change_tracking_mode :changes_only
    store_action_name? true
    attributes_as_attributes [:organization_id]
  end
end
