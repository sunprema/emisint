defmodule Emisint.Assessments.MdeSchoolIndexResult do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "mde_school_index_results"
    repo Emisint.Repo

    custom_indexes do
      index [:mde_building_id, :school_year]
    end
  end

  # ---------------------------------------------------------------------------
  # Module attribute — all metric + support fields updated on upsert conflict
  # ---------------------------------------------------------------------------

  @index_upsert_fields [
    :overall_index,
    :growth_index,
    :proficiency_index,
    :graduation_index,
    :el_progress_index,
    :school_quality_index,
    :subject_participation_index,
    :el_participation_index,
    :support_category_name,
    :support_category_reason
  ]

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :school_year,
        :mde_building_id
        | @index_upsert_fields
      ]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_building_year
      upsert_fields @index_upsert_fields

      accept [
        :school_year,
        :mde_building_id
        | @index_upsert_fields
      ]
    end

    update :update do
      primary? true
      accept @index_upsert_fields
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system_admin) do
      authorize_if always()
    end

    # MDE public data — any authenticated user may read it
    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :system_admin)
    end
  end

  attributes do
    uuid_primary_key :id

    # Matches AcademicYear.label (e.g. "2024-2025") — cross-tenant soft join
    attribute :school_year, :string do
      allow_nil? false
      public? true
    end

    # ── Index scores ──────────────────────────────────────────────────────────

    attribute :overall_index, :decimal do
      allow_nil? true
      public? true
    end

    attribute :growth_index, :decimal do
      allow_nil? true
      public? true
    end

    attribute :proficiency_index, :decimal do
      allow_nil? true
      public? true
    end

    attribute :graduation_index, :decimal do
      allow_nil? true
      public? true
    end

    attribute :el_progress_index, :decimal do
      allow_nil? true
      public? true
    end

    attribute :school_quality_index, :decimal do
      allow_nil? true
      public? true
    end

    attribute :subject_participation_index, :decimal do
      allow_nil? true
      public? true
    end

    attribute :el_participation_index, :decimal do
      allow_nil? true
      public? true
    end

    # ── Support category ─────────────────────────────────────────────────────

    attribute :support_category_name, :string do
      allow_nil? true
      public? true
    end

    attribute :support_category_reason, :string do
      allow_nil? true
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :mde_building, Emisint.Assessments.MdeBuilding do
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end

  identities do
    # One row per building × school year
    identity :unique_building_year, [:mde_building_id, :school_year]
  end
end
