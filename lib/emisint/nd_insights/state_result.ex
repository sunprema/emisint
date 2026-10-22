defmodule Emisint.NdInsights.StateResult do
  @moduledoc """
  One published ND Insights measure for one institution and group, exactly as
  published. See `Emisint.NdInsights.Parser` for the datasets and measures.

    * `value_state` — `:exact` (`value`), `:range` (`range_low`–`range_high`,
      never a midpoint) or `:suppressed` (no value; `source_text` keeps the
      verbatim cell, e.g. `"*"` or empty).
    * Groups the state did not publish have no row.
    * `natural_key` identifies the measure independent of file; together with
      `publication_version` it is unique, so re-importing a file creates
      nothing and a newer state publication is stored alongside the older one
      rather than overwriting it. Readers use the latest version per key.
    * `raw_row` is the full source row, unmodified.
  """
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.NdInsights,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "nd_insights_state_results"
    repo Emisint.Repo

    custom_indexes do
      index [:institution_id, :dataset, :academic_year]
    end
  end

  @dimensions [
    :dataset,
    :academic_year,
    :institution_id,
    :institution_name,
    :entity_level,
    :district_name,
    :subject,
    :grade,
    :assessment_type,
    :accommodations,
    :subgroup,
    :engagement_level,
    :measure
  ]

  @values [:unit, :value_state, :value, :range_low, :range_high, :source_text, :raw_row]

  def dimensions, do: @dimensions

  actions do
    defaults [:read]

    create :import do
      accept @dimensions ++ @values ++ [:natural_key, :publication_version, :source_file_id]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system_admin) do
      authorize_if always()
    end

    # Public state data: readable by any signed-in user.
    policy action_type(:read) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :dataset, :atom do
      allow_nil? false
      public? true
      constraints one_of: Emisint.NdInsights.Parser.datasets()
    end

    attribute :academic_year, :string, allow_nil?: false, public?: true
    attribute :institution_id, :string, allow_nil?: false, public?: true
    attribute :institution_name, :string, public?: true
    attribute :entity_level, :string, public?: true
    attribute :district_name, :string, public?: true
    attribute :subject, :string, public?: true
    attribute :grade, :string, public?: true
    attribute :assessment_type, :string, public?: true
    attribute :accommodations, :string, public?: true
    attribute :subgroup, :string, public?: true
    attribute :engagement_level, :string, public?: true

    attribute :measure, :string do
      allow_nil? false
      public? true
      description "Source column name (e.g. Partially, PercentTested, OverallGrowthLevel)."
    end

    attribute :unit, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:proportion, :level, :percentile]
    end

    attribute :value_state, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:exact, :range, :suppressed]
    end

    attribute :value, :decimal, public?: true
    attribute :range_low, :decimal, public?: true
    attribute :range_high, :decimal, public?: true
    attribute :source_text, :string, public?: true
    attribute :raw_row, :map, allow_nil?: false, default: %{}, public?: true

    attribute :natural_key, :string, allow_nil?: false, public?: true
    attribute :publication_version, :string, allow_nil?: false, public?: true

    create_timestamp :imported_at, public?: true
  end

  relationships do
    belongs_to :source_file, Emisint.NdInsights.SourceFile do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_published_measure, [:natural_key, :publication_version]
  end
end
