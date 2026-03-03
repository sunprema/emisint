defmodule Emisint.Assessments.MdeEnrollmentResult do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "mde_enrollment_results"
    repo Emisint.Repo

    custom_indexes do
      index [:mde_building_id, :school_year]
      index [:mde_district_id, :school_year]
      index [:rollup_level, :school_year]
    end
  end

  # ---------------------------------------------------------------------------
  # Module attribute — all count + string fields updated on upsert conflict
  # ---------------------------------------------------------------------------

  @enrollment_upsert_fields [
    :total_enrollment,
    :male_enrollment,
    :female_enrollment,
    :american_indian_enrollment,
    :asian_enrollment,
    :african_american_enrollment,
    :hispanic_enrollment,
    :hawaiian_enrollment,
    :white_enrollment,
    :two_or_more_races_enrollment,
    :early_middle_college_enrollment,
    :prekindergarten_enrollment,
    :kindergarten_enrollment,
    :grade_1_enrollment,
    :grade_2_enrollment,
    :grade_3_enrollment,
    :grade_4_enrollment,
    :grade_5_enrollment,
    :grade_6_enrollment,
    :grade_7_enrollment,
    :grade_8_enrollment,
    :grade_9_enrollment,
    :grade_10_enrollment,
    :grade_11_enrollment,
    :grade_12_enrollment,
    :ungraded_enrollment,
    :economic_disadvantaged_enrollment,
    :special_education_enrollment,
    :english_language_learners_enrollment,
    :isd_code,
    :isd_name,
    :district_code,
    :district_name,
    :building_code,
    :building_name,
    :county_code,
    :county_name,
    :entity_type,
    :school_level,
    :locale_name,
    :mistem_name,
    :mistem_code
  ]

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :rollup_level,
        :school_year,
        :mde_building_id,
        :mde_district_id,
        :mde_isd_id
        | @enrollment_upsert_fields
      ]
    end

    # Building-level upsert — identity: [:school_year, :mde_building_id]
    create :upsert do
      upsert? true
      upsert_identity :unique_building_enrollment
      upsert_fields @enrollment_upsert_fields

      accept [
        :rollup_level,
        :school_year,
        :mde_building_id
        | @enrollment_upsert_fields
      ]
    end

    # District-level rollup upsert — identity: [:school_year, :mde_district_id]
    create :upsert_district_rollup do
      upsert? true
      upsert_identity :unique_district_enrollment
      upsert_fields @enrollment_upsert_fields

      accept [
        :rollup_level,
        :school_year,
        :mde_district_id
        | @enrollment_upsert_fields
      ]
    end

    # ISD-level rollup upsert — identity: [:school_year, :mde_isd_id]
    create :upsert_isd_rollup do
      upsert? true
      upsert_identity :unique_isd_enrollment
      upsert_fields @enrollment_upsert_fields

      accept [
        :rollup_level,
        :school_year,
        :mde_isd_id
        | @enrollment_upsert_fields
      ]
    end

    update :update do
      primary? true
      accept @enrollment_upsert_fields
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

    # ── Granularity ─────────────────────────────────────────────────────────

    attribute :rollup_level, :atom do
      constraints one_of: [:building, :district, :isd]
      default :building
      allow_nil? false
      public? true
    end

    # Matches AcademicYear.label (e.g. "2022-2023") — cross-tenant soft join
    attribute :school_year, :string do
      allow_nil? false
      public? true
    end

    # ── Denormalized dimension strings ───────────────────────────────────────

    attribute :isd_code, :string do
      allow_nil? true
      public? true
    end

    attribute :isd_name, :string do
      allow_nil? true
      public? true
    end

    attribute :district_code, :string do
      allow_nil? true
      public? true
    end

    attribute :district_name, :string do
      allow_nil? true
      public? true
    end

    attribute :building_code, :string do
      allow_nil? true
      public? true
    end

    attribute :building_name, :string do
      allow_nil? true
      public? true
    end

    attribute :county_code, :string do
      allow_nil? true
      public? true
    end

    attribute :county_name, :string do
      allow_nil? true
      public? true
    end

    attribute :entity_type, :string do
      allow_nil? true
      public? true
    end

    attribute :school_level, :string do
      allow_nil? true
      public? true
    end

    attribute :locale_name, :string do
      allow_nil? true
      public? true
    end

    attribute :mistem_name, :string do
      allow_nil? true
      public? true
    end

    attribute :mistem_code, :string do
      allow_nil? true
      public? true
    end

    # ── Enrollment counts (nil = MDE small-cell suppression) ─────────────────

    attribute :total_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :male_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :female_enrollment, :integer do
      allow_nil? true
      public? true
    end

    # ── Race/Ethnicity counts ────────────────────────────────────────────────

    attribute :american_indian_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :asian_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :african_american_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :hispanic_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :hawaiian_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :white_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :two_or_more_races_enrollment, :integer do
      allow_nil? true
      public? true
    end

    # ── Grade-level counts ───────────────────────────────────────────────────

    attribute :early_middle_college_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :prekindergarten_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :kindergarten_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :grade_1_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :grade_2_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :grade_3_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :grade_4_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :grade_5_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :grade_6_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :grade_7_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :grade_8_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :grade_9_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :grade_10_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :grade_11_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :grade_12_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :ungraded_enrollment, :integer do
      allow_nil? true
      public? true
    end

    # ── Subgroup counts ──────────────────────────────────────────────────────

    attribute :economic_disadvantaged_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :special_education_enrollment, :integer do
      allow_nil? true
      public? true
    end

    attribute :english_language_learners_enrollment, :integer do
      allow_nil? true
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    # Set for building-level rows; nil for district/ISD rollups
    belongs_to :mde_building, Emisint.Assessments.MdeBuilding do
      allow_nil? true
      attribute_writable? true
      public? true
    end

    # Set for district-level rollup rows
    belongs_to :mde_district, Emisint.Assessments.MdeDistrict do
      allow_nil? true
      attribute_writable? true
      public? true
    end

    # Set for ISD-level rollup rows
    belongs_to :mde_isd, Emisint.Assessments.MdeIsd do
      allow_nil? true
      attribute_writable? true
      public? true
    end
  end

  identities do
    # One row per building per year
    identity :unique_building_enrollment, [:school_year, :mde_building_id]

    # One row per district per year (rollup rows)
    identity :unique_district_enrollment, [:school_year, :mde_district_id]

    # One row per ISD per year (rollup rows)
    identity :unique_isd_enrollment, [:school_year, :mde_isd_id]
  end
end
