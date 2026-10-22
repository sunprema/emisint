defmodule Emisint.Improvement.Goal do
  @moduledoc """
  One numbered goal in a `GoalPlan`. `implementation_steps` maps a reporting
  period code to the number of planned implementation steps for that period,
  as listed in the workbook (e.g. `%{"spr_26" => 5}`).
  """
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Improvement,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Emisint.Improvement.Changes.InheritScope
  alias Emisint.Improvement.Checks.CanReadSchoolData

  postgres do
    table "improvement_goals"
    repo Emisint.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:goal_plan_id, :number, :title, :description, :implementation_steps, :source_ref]

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

    attribute :number, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :implementation_steps, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :source_ref, :string do
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

    has_many :metrics, Emisint.Improvement.Metric do
      sort position: :asc
      public? true
    end
  end

  identities do
    identity :unique_number, [:goal_plan_id, :number]
  end
end
