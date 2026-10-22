defmodule Emisint.Improvement.AnnualAssessmentGoal do
  @moduledoc """
  A school's annual state assessment target from its continuous improvement
  plan (e.g. Fort Yates 2025–2026 ELA 25%). These are "Proficient or
  Advanced" targets including the alternate assessment — kept separate from
  MOU metrics that count only "Proficient".
  """
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Improvement,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Emisint.Improvement.Changes.InheritScope
  alias Emisint.Improvement.Checks.CanReadSchoolData

  postgres do
    table "improvement_annual_assessment_goals"
    repo Emisint.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :school_id,
        :school_year,
        :subject,
        :target_value,
        :measure,
        :includes_alternate,
        :source_ref
      ]

      change {InheritScope, from: :school_id, resource: Emisint.Accounts.School, copy: []}
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

    attribute :school_year, :string do
      allow_nil? false
      public? true
      constraints match: "^\\d{4}-\\d{4}$"
    end

    attribute :subject, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:ela, :math]
    end

    attribute :target_value, :decimal do
      allow_nil? false
      public? true
      constraints min: 0, max: 1
    end

    attribute :measure, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:proficient_or_advanced]
    end

    attribute :includes_alternate, :boolean do
      allow_nil? false
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
      attribute_writable? true
      public? true
    end
  end

  identities do
    identity :unique_year_subject, [:school_id, :school_year, :subject]
  end
end
