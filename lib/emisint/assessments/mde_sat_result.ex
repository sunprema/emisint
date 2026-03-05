defmodule Emisint.Assessments.MdeSatResult do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "mde_sat_results"
    repo Emisint.Repo

    custom_indexes do
      index [:mde_building_id, :school_year]
      index [:mde_district_id, :school_year]
      index [:rollup_level, :school_year, :subgroup]
    end
  end

  # ---------------------------------------------------------------------------
  # Module attribute — all metric + denorm fields updated on upsert conflict
  # ---------------------------------------------------------------------------

  @sat_upsert_fields [
    :math_percent_ready,
    :math_num_assessed,
    :math_score_average,
    :math_count_ready,
    :reading_percent_ready,
    :reading_num_assessed,
    :reading_score_average,
    :science_percent_ready,
    :science_num_assessed,
    :science_score_average,
    :english_percent_ready,
    :english_num_assessed,
    :english_score_average,
    :all_subject_percent_ready,
    :all_subject_num_assessed,
    :all_subject_score_average,
    :all_count_ready,
    :ebrw_percent_ready,
    :ebrw_num_assessed,
    :ebrw_score_average,
    :ebrw_count_ready,
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
    :locale,
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
        :subgroup,
        :mde_building_id,
        :mde_district_id,
        :mde_isd_id
        | @sat_upsert_fields
      ]
    end

    # Building-level upsert — identity: [:mde_building_id, :school_year, :subgroup]
    create :upsert do
      upsert? true
      upsert_identity :unique_building_sat
      upsert_fields @sat_upsert_fields

      accept [
        :rollup_level,
        :school_year,
        :subgroup,
        :mde_building_id
        | @sat_upsert_fields
      ]
    end

    # District-level rollup upsert — identity: [:mde_district_id, :rollup_level, :school_year, :subgroup]
    create :upsert_district_rollup do
      upsert? true
      upsert_identity :unique_district_sat
      upsert_fields @sat_upsert_fields

      accept [
        :rollup_level,
        :school_year,
        :subgroup,
        :mde_district_id
        | @sat_upsert_fields
      ]
    end

    # ISD-level rollup upsert — identity: [:mde_isd_id, :rollup_level, :school_year, :subgroup]
    create :upsert_isd_rollup do
      upsert? true
      upsert_identity :unique_isd_sat
      upsert_fields @sat_upsert_fields

      accept [
        :rollup_level,
        :school_year,
        :subgroup,
        :mde_isd_id
        | @sat_upsert_fields
      ]
    end

    update :update do
      primary? true
      accept @sat_upsert_fields
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

    # ESSA subgroup / demographic slice (e.g. "All Students", "Economically Disadvantaged")
    attribute :subgroup, :string do
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

    attribute :locale, :string do
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

    # ── Math ─────────────────────────────────────────────────────────────────

    attribute :math_percent_ready, :decimal do
      allow_nil? true
      public? true
    end

    attribute :math_num_assessed, :integer do
      allow_nil? true
      public? true
    end

    attribute :math_score_average, :decimal do
      allow_nil? true
      public? true
    end

    attribute :math_count_ready, :integer do
      allow_nil? true
      public? true
    end

    # ── Reading ──────────────────────────────────────────────────────────────

    attribute :reading_percent_ready, :decimal do
      allow_nil? true
      public? true
    end

    attribute :reading_num_assessed, :integer do
      allow_nil? true
      public? true
    end

    attribute :reading_score_average, :decimal do
      allow_nil? true
      public? true
    end

    # ── Science ──────────────────────────────────────────────────────────────

    attribute :science_percent_ready, :decimal do
      allow_nil? true
      public? true
    end

    attribute :science_num_assessed, :integer do
      allow_nil? true
      public? true
    end

    attribute :science_score_average, :decimal do
      allow_nil? true
      public? true
    end

    # ── English ──────────────────────────────────────────────────────────────

    attribute :english_percent_ready, :decimal do
      allow_nil? true
      public? true
    end

    attribute :english_num_assessed, :integer do
      allow_nil? true
      public? true
    end

    attribute :english_score_average, :decimal do
      allow_nil? true
      public? true
    end

    # ── All Subjects ─────────────────────────────────────────────────────────

    attribute :all_subject_percent_ready, :decimal do
      allow_nil? true
      public? true
    end

    attribute :all_subject_num_assessed, :integer do
      allow_nil? true
      public? true
    end

    attribute :all_subject_score_average, :decimal do
      allow_nil? true
      public? true
    end

    attribute :all_count_ready, :integer do
      allow_nil? true
      public? true
    end

    # ── EBRW (Evidence-Based Reading and Writing) ─────────────────────────────

    attribute :ebrw_percent_ready, :decimal do
      allow_nil? true
      public? true
    end

    attribute :ebrw_num_assessed, :integer do
      allow_nil? true
      public? true
    end

    attribute :ebrw_score_average, :decimal do
      allow_nil? true
      public? true
    end

    attribute :ebrw_count_ready, :integer do
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
    # One row per building × school year × subgroup
    identity :unique_building_sat, [:mde_building_id, :school_year, :subgroup]

    # One row per district × rollup level × school year × subgroup
    identity :unique_district_sat, [:mde_district_id, :rollup_level, :school_year, :subgroup]

    # One row per ISD × rollup level × school year × subgroup
    identity :unique_isd_sat, [:mde_isd_id, :rollup_level, :school_year, :subgroup]
  end
end
