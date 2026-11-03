defmodule Emisint.Improvement.GoalPlan do
  @moduledoc """
  A school's goal plan (e.g. the ND First MOU). Holds the payment rule inputs
  so they are stored, visible and testable rather than hard-coded: payment cap,
  category weights and maximum rating.

  Read-only in the pilot. Changing a definition later requires a new
  `definition_version` or an audited update, not an in-place edit.
  """
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Improvement,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Emisint.Improvement.Changes.InheritScope
  alias Emisint.Improvement.Checks.CanReadSchoolData
  alias Emisint.Improvement.Validations.PaymentTerms

  @terms_fields [
    :payment_cap,
    :allocation_18m,
    :allocation_36m,
    :payment_terms_status,
    :payment_terms_note
  ]

  postgres do
    table "improvement_goal_plans"
    repo Emisint.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :school_id,
        :program,
        :name,
        :definition_version,
        :progress_doc_url,
        :payment_cap,
        :systems_weight,
        :outcomes_weight,
        :max_rating,
        :source_note,
        :allocation_18m,
        :allocation_36m,
        :payment_terms_status,
        :payment_terms_note
      ]

      change {InheritScope, from: :school_id, resource: Emisint.Accounts.School, copy: []}
      validate PaymentTerms
    end

    update :set_payment_terms do
      description """
      Set the payment cap, checkpoint allocations and their status (system
      only; no user policy). Bumps `payment_terms_version` whenever a value
      changes, so a recorded estimate can name the terms it used.
      """

      accept @terms_fields
      require_atomic? false

      validate PaymentTerms

      change fn changeset, _context ->
        if Enum.any?(@terms_fields, &Ash.Changeset.changing_attribute?(changeset, &1)) do
          Ash.Changeset.force_change_attribute(
            changeset,
            :payment_terms_version,
            (changeset.data.payment_terms_version || 0) + 1
          )
        else
          changeset
        end
      end
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

    attribute :program, :string do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :definition_version, :integer do
      allow_nil? false
      default 1
      public? true
      constraints min: 1
    end

    attribute :progress_doc_url, :string do
      public? true
    end

    attribute :payment_cap, :decimal do
      public? true
      constraints min: 0
    end

    attribute :systems_weight, :decimal do
      public? true
      constraints min: 0, max: 1

      description "The 18-month review weight from the payment sheet. Weights differ by checkpoint; \
use `Emisint.Improvement.Payment.checkpoints/1`."
    end

    attribute :outcomes_weight, :decimal do
      public? true
      constraints min: 0, max: 1

      description "The 18-month review weight from the payment sheet. Weights differ by checkpoint; \
use `Emisint.Improvement.Payment.checkpoints/1`."
    end

    attribute :allocation_18m, :decimal do
      public? true
      constraints min: 0
      description "Share of `payment_cap` allocated to the 18-month review."
    end

    attribute :allocation_36m, :decimal do
      public? true
      constraints min: 0
      description "Share of `payment_cap` allocated to the 36-month review."
    end

    attribute :payment_terms_status, :atom do
      allow_nil? false
      default :unconfirmed
      public? true
      constraints one_of: [:unconfirmed, :provisional, :confirmed]
      description "Whether the cap and allocations are confirmed contract terms."
    end

    attribute :payment_terms_note, :string do
      public? true
      description "Who authorized the terms and why (e.g. a provisional working assumption)."
    end

    attribute :payment_terms_version, :integer do
      allow_nil? false
      default 1
      public? true
      constraints min: 1
    end

    attribute :max_rating, :integer do
      allow_nil? false
      default 3
      public? true
      constraints min: 1
    end

    attribute :source_note, :string do
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

    has_many :goals, Emisint.Improvement.Goal do
      sort number: :asc
      public? true
    end

    has_many :metrics, Emisint.Improvement.Metric do
      sort position: :asc
      public? true
    end

    has_many :reporting_periods, Emisint.Improvement.ReportingPeriod do
      sort position: :asc
      public? true
    end
  end

  identities do
    identity :unique_program_version, [:school_id, :program, :definition_version]
  end
end
