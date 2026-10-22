defmodule Emisint.Improvement.ReportingPeriod do
  @moduledoc """
  A reporting period in a `GoalPlan`: seasonal update windows (Spr '26,
  Sum '26, …) and the 18-/36-month formal reviews. Dates are nullable because
  the exact windows and review dates are not yet known.
  """
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Improvement,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Emisint.Improvement.Changes.InheritScope
  alias Emisint.Improvement.Checks.CanReadSchoolData

  postgres do
    table "improvement_reporting_periods"
    repo Emisint.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :goal_plan_id,
        :code,
        :label,
        :kind,
        :position,
        :source_column,
        :starts_on,
        :ends_on
      ]

      change {InheritScope,
              from: :goal_plan_id,
              resource: Emisint.Improvement.GoalPlan,
              copy: [school_id: :school_id]}
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

    attribute :label, :string do
      allow_nil? false
      public? true
    end

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:seasonal, :review_18m, :review_36m]
    end

    attribute :position, :integer do
      allow_nil? false
      public? true
    end

    attribute :source_column, :string do
      public? true
    end

    attribute :starts_on, :date do
      public? true
    end

    attribute :ends_on, :date do
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
      attribute_writable? true
      public? true
    end
  end

  identities do
    identity :unique_code, [:goal_plan_id, :code]
  end
end
