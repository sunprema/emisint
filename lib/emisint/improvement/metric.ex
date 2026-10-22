defmodule Emisint.Improvement.Metric do
  @moduledoc """
  A goal metric with its baseline and 18-/36-month targets.

  For `unit: :percent` the normalized fields (`baseline_value`, `target_18m`,
  `target_36m`) are proportions in 0–1. A source value that cannot be
  normalized with confidence is **not** stored in those fields: it is kept
  verbatim in `source_values` and the metric is flagged (e.g.
  `:target_36m_needs_confirmation`), leaving the target unset so it is excluded
  from calculations.

  `direction` records whether lower values are better (novice and
  disengagement metrics). `performance_measure` keeps "Proficient" distinct
  from "Proficient or Advanced".
  """
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Improvement,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Emisint.Improvement.Changes.InheritScope
  alias Emisint.Improvement.Checks.CanReadSchoolData
  alias Emisint.Improvement.Validations.PercentBounds

  @flags [
    :target_36m_needs_confirmation,
    :review_18m_column_heading_unconfirmed
  ]

  postgres do
    table "improvement_metrics"
    repo Emisint.Repo

    custom_indexes do
      index [:goal_id]
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :goal_id,
        :code,
        :description,
        :category,
        :unit,
        :direction,
        :performance_measure,
        :baseline_value,
        :target_18m,
        :target_36m,
        :source_values,
        :flags,
        :position
      ]

      change {InheritScope,
              from: :goal_id,
              resource: Emisint.Improvement.Goal,
              copy: [school_id: :school_id, goal_plan_id: :goal_plan_id]}

      validate {PercentBounds, fields: [:baseline_value, :target_18m, :target_36m]}
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system_admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if {CanReadSchoolData, via: :school}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_primary_key :id

    attribute :code, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      allow_nil? false
      public? true
    end

    attribute :category, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:systems, :student_outcome]
    end

    attribute :unit, :atom do
      allow_nil? false
      default :percent
      public? true
      constraints one_of: [:percent]
    end

    attribute :direction, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:higher_is_better, :lower_is_better]
    end

    attribute :performance_measure, :atom do
      allow_nil? false
      default :other
      public? true
      constraints one_of: [:proficient, :novice, :met_growth_expectation, :other]
    end

    attribute :baseline_value, :decimal do
      public? true
    end

    attribute :target_18m, :decimal do
      public? true
    end

    attribute :target_36m, :decimal do
      public? true
    end

    attribute :source_values, :map do
      allow_nil? false
      default %{}
      public? true

      description "Original source cells, e.g. %{\"target_36m\" => %{\"cell\" => \"P7\", \"raw\" => \"90\"}}"
    end

    attribute :flags, {:array, :atom} do
      allow_nil? false
      default []
      public? true
      constraints items: [one_of: @flags]
    end

    attribute :position, :integer do
      allow_nil? false
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Emisint.Accounts.Organization do
      allow_nil? false
      public? true
    end

    belongs_to :school, Emisint.Accounts.School do
      allow_nil? false
      public? true
    end

    belongs_to :goal_plan, Emisint.Improvement.GoalPlan do
      allow_nil? false
      public? true
    end

    belongs_to :goal, Emisint.Improvement.Goal do
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end

  identities do
    identity :unique_code, [:goal_plan_id, :code]
  end
end
