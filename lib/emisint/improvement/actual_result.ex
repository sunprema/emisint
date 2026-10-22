defmodule Emisint.Improvement.ActualResult do
  @moduledoc """
  An append-only actual result for a metric in a seasonal reporting period.

  Entries are never updated or deleted:

    * `:record`  — the first value (`kind: :observation`) for a metric × period
    * `:correct` — a `kind: :correction` that replaces exactly one current entry

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

  alias Emisint.Improvement.Changes.{ScopeEntry, SetActor}
  alias Emisint.Improvement.Checks.{CanReadSchoolData, CanWriteSchoolData}
  alias Emisint.Improvement.Validations.{ActualValueShape, PercentBounds}

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
      description "Record the first actual result for a metric in a seasonal period."
      accept [:metric_id, :reporting_period_id | @value_fields]

      change {ScopeEntry, kind: :observation, period_kinds: [:seasonal]}
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

    policy action_type(:create) do
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
      constraints one_of: [:manual]
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
