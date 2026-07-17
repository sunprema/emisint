defmodule Emisint.Assessments.MdeSgpResult do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @moduledoc """
  MDE Student Growth Percentile (SGP) results — one row per (building OR LEA
  district) × school year × grade × subject × testing group (subgroup).

  `rollup_level` distinguishes building-level rows from district-level rollup
  rows, mirroring the nullable-relationship pattern used by
  `MdeStateAssessmentResult`. ISD/statewide rollup rows in the source CSV are
  still skipped by `MdeSgpImporter` — out of scope for the school-vs-LEA
  comparison this resource exists to support.
  """

  postgres do
    table "mde_sgp_results"
    repo Emisint.Repo

    custom_indexes do
      index [:mde_building_id, :school_year]
      index [:mde_district_id, :school_year]
      index [:rollup_level, :school_year, :subject]
    end
  end

  @upsert_fields [
    :testing_group,
    :number_above_average_growth,
    :number_average_growth,
    :number_below_average_growth,
    :percent_above_average,
    :percent_average_growth,
    :percent_below_average,
    :total_included,
    :mean_sgp
  ]

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :rollup_level,
        :school_year,
        :grade,
        :subject,
        :mde_building_id,
        :mde_district_id
        | @upsert_fields
      ]
    end

    # Building-level upsert
    create :upsert do
      upsert? true
      upsert_identity :unique_building_grade_subject_group
      upsert_fields @upsert_fields

      accept [
        :rollup_level,
        :school_year,
        :grade,
        :subject,
        :mde_building_id
        | @upsert_fields
      ]
    end

    # District-level (LEA) rollup upsert
    create :upsert_district_rollup do
      upsert? true
      upsert_identity :unique_district_grade_subject_group
      upsert_fields @upsert_fields

      accept [
        :rollup_level,
        :school_year,
        :grade,
        :subject,
        :mde_district_id
        | @upsert_fields
      ]
    end

    update :update do
      primary? true
      accept @upsert_fields
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

    # Distinguishes building-level rows from district (LEA) rollup rows
    attribute :rollup_level, :atom do
      constraints one_of: [:building, :district]
      default :building
      allow_nil? false
      public? true
    end

    # Matches AcademicYear.label-style formatting (e.g. "2024-2025")
    attribute :school_year, :string do
      allow_nil? false
      public? true
    end

    attribute :grade, :string do
      allow_nil? false
      public? true
    end

    # Free text (e.g. "Mathematics", "English Language Arts", "Science",
    # "Social Studies") — stored as-is, not constrained, since the exact MDE
    # literal values aren't hardcoded anywhere else in the codebase either.
    attribute :subject, :string do
      allow_nil? false
      public? true
    end

    # Student subgroup (e.g. "All Students", "Economically Disadvantaged").
    # Every subgroup row is imported and stored even though v1 display only
    # surfaces "All Students" — future subgroup breakdowns are then just a
    # query away, not a re-import.
    attribute :testing_group, :string do
      allow_nil? true
      public? true
    end

    # ── Growth band counts + percentages ────────────────────────────────────
    # Privacy-suppressed cells (raw CSV values like "< 10" / "< 5") are parsed
    # to nil by MdeSgpImporter rather than stored as text — the UI renders a
    # muted "—" for any nil cell.

    attribute :number_above_average_growth, :integer do
      allow_nil? true
      public? true
    end

    attribute :number_average_growth, :integer do
      allow_nil? true
      public? true
    end

    attribute :number_below_average_growth, :integer do
      allow_nil? true
      public? true
    end

    attribute :percent_above_average, :decimal do
      allow_nil? true
      public? true
    end

    attribute :percent_average_growth, :decimal do
      allow_nil? true
      public? true
    end

    attribute :percent_below_average, :decimal do
      allow_nil? true
      public? true
    end

    attribute :total_included, :integer do
      allow_nil? true
      public? true
    end

    # The headline metric — 1-99 scale, 50 = median/typical growth.
    attribute :mean_sgp, :decimal do
      allow_nil? true
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    # Nullable: district-rollup rows have no specific building
    belongs_to :mde_building, Emisint.Assessments.MdeBuilding do
      allow_nil? true
      attribute_writable? true
      public? true
    end

    # Set for district-level (LEA) rollup rows
    belongs_to :mde_district, Emisint.Assessments.MdeDistrict do
      allow_nil? true
      attribute_writable? true
      public? true
    end
  end

  identities do
    identity :unique_building_grade_subject_group, [
      :mde_building_id,
      :school_year,
      :grade,
      :subject,
      :testing_group
    ]

    identity :unique_district_grade_subject_group, [
      :mde_district_id,
      :rollup_level,
      :school_year,
      :grade,
      :subject,
      :testing_group
    ]
  end
end
