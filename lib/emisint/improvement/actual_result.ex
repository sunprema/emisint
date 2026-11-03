defmodule Emisint.Improvement.ActualResult do
  @moduledoc """
  An append-only actual result for a metric in a reporting period: a
  seasonal update or the 18-/36-month review (actual-result entry only;
  review ratings and payment scoring are separate, Phase 3).

  Entries are never updated or deleted:

    * `:record`  — the first value (`kind: :observation`) for a metric × period
    * `:correct` — a `kind: :correction` that replaces exactly one current entry
    * `:record_published` / `:correct_published` — the same, taking the value
      from a published ND Insights row for an explicit `source_year`
      (growth-percentile metrics at a review only; `Changes.FromNdInsights`).
      `source: :nd_insights`, and `source_ref` names the year, population,
      measure, publication version and file.
    * `:convert_unit` — a system restatement after a unit decision
      (`GrowthPercentile.run/2`); no policy allows it for other users

  The **current** entry for a metric × period is the one no other entry
  corrects. It is defined structurally, never by timestamp. A partial unique
  index allows one observation per metric × period, and a unique index on
  `corrects_id` rejects a second, concurrent correction of the same entry.

  `value_state` supports exact, ranged, suppressed and unavailable results;
  see `Validations.ActualValueShape`. Percent values are normalized to 0–1.

  Provenance: `author_id` is the original author (nil when unknown),
  `recorded_by_id` and `recorded_at` are set by the server.
  """
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Improvement,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Emisint.Improvement.Changes.{FromNdInsights, ScopeEntry, SetActor}
  alias Emisint.Improvement.Checks.{CanReadSchoolData, CanWriteSchoolData}
  alias Emisint.Improvement.Validations.{ActualValueShape, PercentBounds}

  @review_kinds [:review_18m, :review_36m]

  @value_fields [
    :value_state,
    :value,
    :range_low,
    :range_high,
    :suppression_reason,
    :measurement_date,
    :notes,
    :evidence_links
  ]

  postgres do
    table "improvement_actual_results"
    repo Emisint.Repo

    identity_wheres_to_sql unique_observation: "kind = 'observation'"

    custom_indexes do
      index [:metric_id, :reporting_period_id]
    end
  end

  actions do
    defaults [:read]

    create :record do
      description "Record the first actual result for a metric in a period."
      accept [:metric_id, :reporting_period_id | @value_fields]

      change {ScopeEntry, kind: :observation, period_kinds: [:seasonal | @review_kinds]}
      change set_attribute(:source, :manual)
      change {SetActor, attribute: :author_id, required?: true}
      change {SetActor, attribute: :recorded_by_id}

      validate {ActualValueShape, require_measurement_date?: true}
      validate {PercentBounds, fields: [:value, :range_low, :range_high]}
    end

    create :correct do
      description "Replace the current actual result for a metric × period."
      accept [:metric_id, :reporting_period_id, :correction_reason | @value_fields]

      argument :corrects_id, :uuid, allow_nil?: false

      change {ScopeEntry, kind: :correction}
      change set_attribute(:source, :manual)
      change {SetActor, attribute: :author_id, required?: true}
      change {SetActor, attribute: :recorded_by_id}

      validate present(:correction_reason), message: "is required for a correction"
      validate {ActualValueShape, require_measurement_date?: true}
      validate {PercentBounds, fields: [:value, :range_low, :range_high]}
    end

    create :record_published do
      description "Record a review result from a published ND Insights value."
      accept [:metric_id, :reporting_period_id, :notes]

      argument :source_year, :string, allow_nil?: false

      change {ScopeEntry, kind: :observation, period_kinds: @review_kinds}
      change {SetActor, attribute: :author_id, required?: true}
      change {SetActor, attribute: :recorded_by_id}
      change FromNdInsights

      validate {ActualValueShape, require_measurement_date?: false}
      validate {PercentBounds, fields: [:value, :range_low, :range_high]}
    end

    create :correct_published do
      description "Replace the current review result with a published ND Insights value."
      accept [:metric_id, :reporting_period_id, :correction_reason, :notes]

      argument :corrects_id, :uuid, allow_nil?: false
      argument :source_year, :string, allow_nil?: false

      change {ScopeEntry, kind: :correction}
      change {SetActor, attribute: :author_id, required?: true}
      change {SetActor, attribute: :recorded_by_id}
      change FromNdInsights

      validate present(:correction_reason), message: "is required for a correction"
      validate {ActualValueShape, require_measurement_date?: false}
      validate {PercentBounds, fields: [:value, :range_low, :range_high]}
    end

    create :convert_unit do
      description "Restate a current result in its metric's corrected unit (system only)."
      accept [:correction_reason, :source_ref, :author_id | @value_fields]

      argument :corrects_id, :uuid, allow_nil?: false

      change {ScopeEntry, kind: :correction}
      change set_attribute(:source, :unit_conversion)
      change {SetActor, attribute: :recorded_by_id}

      validate present(:correction_reason)
      validate present(:source_ref)
      validate {ActualValueShape, require_measurement_date?: false}
      validate {PercentBounds, fields: [:value, :range_low, :range_high]}
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

    # :convert_unit has no policy, so only the system (or a system admin) can run it.
    policy action([:record, :correct, :record_published, :correct_published]) do
      authorize_if {CanWriteSchoolData, roles: [:contributor]}
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

    attribute :value_state, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:exact, :range, :suppressed, :unavailable]
    end

    attribute :value, :decimal do
      public? true
    end

    attribute :range_low, :decimal do
      public? true
    end

    attribute :range_high, :decimal do
      public? true
    end

    attribute :suppression_reason, :string do
      public? true
      description "Verbatim reason stated by the source, if any."
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
      constraints one_of: [:manual, :nd_insights, :unit_conversion]
    end

    attribute :source_ref, :string do
      public? true
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
      message: "already has a value for this period; submit a correction instead"

    identity :unique_correction, [:corrects_id],
      message: "has already been corrected; correct the current entry instead"
  end
end
