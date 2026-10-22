defmodule Emisint.Improvement.ImplementationRating do
  @moduledoc """
  An append-only seasonal implementation rating (0–3) for a metric. Separate
  from `ActualResult`, so a rating update never hides an actual result and
  vice versa. Never used for payment calculations.

  Rubric: 3 Demonstrated Progress, 2 Implementation on Track, 1 Some Progress,
  0 Not Started. A 3 means demonstrated progress, not that the target was met.

  Same observation/correction model as `ActualResult`. The `:import_workbook`
  action loads historical workbook ratings: no author, no measurement date,
  the workbook's own last-updated date in `source_last_updated_on`, and the
  importing actor (if any) in `recorded_by_id`.
  """
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Improvement,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Emisint.Improvement.Changes.{ScopeEntry, SetActor}
  alias Emisint.Improvement.Checks.{CanReadSchoolData, CanWriteSchoolData}
  alias Emisint.Improvement.Validations.RatingShape

  @value_fields [:rating_state, :score, :measurement_date, :notes, :evidence_links]

  postgres do
    table "improvement_implementation_ratings"
    repo Emisint.Repo

    identity_wheres_to_sql unique_observation: "kind = 'observation'"

    custom_indexes do
      index [:metric_id, :reporting_period_id]
    end
  end

  actions do
    defaults [:read]

    create :record do
      description "Record the first seasonal implementation rating for a metric in a period."
      accept [:metric_id, :reporting_period_id | @value_fields]

      change {ScopeEntry, kind: :observation, period_kinds: [:seasonal]}
      change set_attribute(:source, :manual)
      change {SetActor, attribute: :author_id, required?: true}
      change {SetActor, attribute: :recorded_by_id}

      validate RatingShape
    end

    create :correct do
      description "Replace the current implementation rating for a metric × period."
      accept [:metric_id, :reporting_period_id, :correction_reason | @value_fields]

      argument :corrects_id, :uuid, allow_nil?: false

      change {ScopeEntry, kind: :correction}
      change set_attribute(:source, :manual)
      change {SetActor, attribute: :author_id, required?: true}
      change {SetActor, attribute: :recorded_by_id}

      validate present(:correction_reason), message: "is required for a correction"
      validate RatingShape
    end

    create :import_workbook do
      description "Import a historical rating from the ND First goal workbook. The original author is unknown."

      accept [
        :metric_id,
        :reporting_period_id,
        :rating_state,
        :score,
        :source_ref,
        :source_last_updated_on
      ]

      change {ScopeEntry, kind: :observation, period_kinds: [:seasonal]}
      change set_attribute(:source, :workbook_import)
      change {SetActor, attribute: :recorded_by_id}

      validate present([:source_ref, :source_last_updated_on])
      validate RatingShape
    end

    read :current do
      filter expr(not exists(correction, true))
      prepare build(sort: [recorded_at: :desc])
    end

    read :history do
      argument :metric_id, :uuid, allow_nil?: false
      filter expr(metric_id == ^arg(:metric_id))
      prepare build(sort: [recorded_at: :desc])
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system_admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if {CanReadSchoolData, via: :school}
    end

    policy action([:record, :correct]) do
      authorize_if {CanWriteSchoolData, roles: [:contributor]}
    end

    policy action(:import_workbook) do
      authorize_if {CanWriteSchoolData, roles: []}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:observation, :correction]
    end

    attribute :rating_state, :atom do
      allow_nil? false
      default :rated
      public? true
      constraints one_of: [:rated, :not_applicable, :unavailable]
    end

    attribute :score, :integer do
      public? true
      constraints min: 0, max: 3
    end

    attribute :measurement_date, :date do
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    attribute :evidence_links, {:array, Emisint.Improvement.EvidenceLink} do
      allow_nil? false
      default []
      public? true
    end

    attribute :correction_reason, :string do
      public? true
    end

    attribute :source, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:manual, :workbook_import]
    end

    attribute :source_ref, :string do
      public? true
      description "e.g. \"Ft Yates Goals!E4\""
    end

    attribute :source_last_updated_on, :date do
      public? true
      description "Last-updated date stated by the source (distinct from recorded_at)."
    end

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

    belongs_to :metric, Emisint.Improvement.Metric do
      allow_nil? false
      attribute_writable? true
      public? true
    end

    belongs_to :reporting_period, Emisint.Improvement.ReportingPeriod do
      allow_nil? false
      attribute_writable? true
      public? true
    end

    belongs_to :corrects, __MODULE__ do
      public? true
    end

    has_one :correction, __MODULE__ do
      destination_attribute :corrects_id
      public? true
    end

    belongs_to :author, Emisint.Accounts.User do
      public? true
    end

    belongs_to :recorded_by, Emisint.Accounts.User do
      public? true
    end
  end

  calculations do
    calculate :current?, :boolean, expr(not exists(correction, true)) do
      public? true
    end
  end

  identities do
    identity :unique_observation, [:metric_id, :reporting_period_id],
      where: expr(kind == :observation),
      message: "already has a rating for this period; submit a correction instead"

    identity :unique_correction, [:corrects_id],
      message: "has already been corrected; correct the current entry instead"
  end
end
