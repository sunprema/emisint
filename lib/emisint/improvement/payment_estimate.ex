defmodule Emisint.Improvement.PaymentEstimate do
  @moduledoc """
  A recorded **estimated** payment for one checkpoint (18- or 36-month
  review), append-only. The amount is computed on the server
  (`Changes.ComputeEstimate`) from the formal review ratings, and the record
  keeps every assumption used — cap, checkpoint allocation, weights, maximum
  rating, the terms' status, version and note, the formula and each rating
  (id and score) — so a later change to the plan's payment terms never
  rewrites a recorded estimate.

  This is not an actual payment; Emisint records none.
  """
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Improvement,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Emisint.Improvement.Changes.{ComputeEstimate, SetActor}
  alias Emisint.Improvement.Checks.{CanReadSchoolData, CanWriteSchoolData}

  postgres do
    table "improvement_payment_estimates"
    repo Emisint.Repo

    custom_indexes do
      # Not tenant-prefixed: matches the hand-written migration
      # 20261101180000_add_provisional_payment_estimates (school implies tenant).
      index [:school_id, :checkpoint], all_tenants?: true
    end
  end

  actions do
    defaults [:read]

    create :record do
      description "Record the current estimate for a complete review checkpoint, with its assumptions."
      accept [:reporting_period_id, :notes]

      change ComputeEstimate
      change {SetActor, attribute: :recorded_by_id, required?: true}
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system_admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if {CanReadSchoolData, via: :school}
    end

    # Org admins only: recording an estimate is a payment-related step.
    policy action(:record) do
      authorize_if {CanWriteSchoolData, roles: []}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_primary_key :id

    attribute :checkpoint, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:review_18m, :review_36m]
    end

    attribute :amount, :decimal, allow_nil?: false, public?: true
    attribute :allocation, :decimal, allow_nil?: false, public?: true
    attribute :payment_cap, :decimal, allow_nil?: false, public?: true
    attribute :systems_weight, :decimal, allow_nil?: false, public?: true
    attribute :outcomes_weight, :decimal, allow_nil?: false, public?: true
    attribute :max_rating, :integer, allow_nil?: false, public?: true
    attribute :systems_average, :decimal, allow_nil?: false, public?: true
    attribute :outcomes_average, :decimal, allow_nil?: false, public?: true
    attribute :weighted_score, :decimal, allow_nil?: false, public?: true

    attribute :terms_status, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:unconfirmed, :provisional, :confirmed]
    end

    attribute :terms_version, :integer, allow_nil?: false, public?: true
    attribute :terms_note, :string, public?: true
    attribute :label, :string, allow_nil?: false, public?: true
    attribute :formula, :string, allow_nil?: false, public?: true

    attribute :inputs, {:array, :map} do
      allow_nil? false
      default []
      public? true
      description "Each rating used: metric code, category, rating id and score."
    end

    attribute :notes, :string, public?: true

    create_timestamp :recorded_at, public?: true
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

    belongs_to :reporting_period, Emisint.Improvement.ReportingPeriod do
      allow_nil? false
      attribute_writable? true
      public? true
    end

    belongs_to :recorded_by, Emisint.Accounts.User do
      allow_nil? false
      public? true
    end
  end
end
