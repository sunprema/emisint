defmodule Emisint.Assessments.MdeStateAssessmentResult do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "mde_state_assessment_results"
    repo Emisint.Repo

    custom_indexes do
      index [:mde_building_id, :school_year]
      index [:mde_district_id, :school_year]
      index [:rollup_level, :school_year, :subject]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :rollup_level,
        :school_year,
        :test_type,
        :test_population,
        :grade_content_tested,
        :subject,
        :report_category,
        :total_advanced,
        :total_proficient,
        :total_partially_proficient,
        :total_not_proficient,
        :total_surpassed,
        :total_attained,
        :total_emerging_towards,
        :total_met,
        :total_did_not_meet,
        :number_assessed,
        :percent_advanced,
        :percent_proficient,
        :percent_partially_proficient,
        :percent_not_proficient,
        :percent_surpassed,
        :percent_attained,
        :percent_emerging_towards,
        :percent_met,
        :percent_met_suppressed,
        :percent_met_approximate,
        :percent_did_not_meet,
        :avg_ss,
        :std_dev_ss,
        :mean_pts_earned,
        :min_scale_score,
        :max_scale_score,
        :scale_score_25,
        :scale_score_50,
        :scale_score_75,
        :mde_building_id,
        :mde_district_id,
        :mde_isd_id
      ]
    end

    # Building-level upsert (existing)
    create :upsert do
      upsert? true
      upsert_identity :unique_result

      upsert_fields [
        :total_advanced,
        :total_proficient,
        :total_partially_proficient,
        :total_not_proficient,
        :total_surpassed,
        :total_attained,
        :total_emerging_towards,
        :total_met,
        :total_did_not_meet,
        :number_assessed,
        :percent_advanced,
        :percent_proficient,
        :percent_partially_proficient,
        :percent_not_proficient,
        :percent_surpassed,
        :percent_attained,
        :percent_emerging_towards,
        :percent_met,
        :percent_met_suppressed,
        :percent_met_approximate,
        :percent_did_not_meet,
        :avg_ss,
        :std_dev_ss,
        :mean_pts_earned,
        :min_scale_score,
        :max_scale_score,
        :scale_score_25,
        :scale_score_50,
        :scale_score_75
      ]

      accept [
        :rollup_level,
        :school_year,
        :test_type,
        :test_population,
        :grade_content_tested,
        :subject,
        :report_category,
        :total_advanced,
        :total_proficient,
        :total_partially_proficient,
        :total_not_proficient,
        :total_surpassed,
        :total_attained,
        :total_emerging_towards,
        :total_met,
        :total_did_not_meet,
        :number_assessed,
        :percent_advanced,
        :percent_proficient,
        :percent_partially_proficient,
        :percent_not_proficient,
        :percent_surpassed,
        :percent_attained,
        :percent_emerging_towards,
        :percent_met,
        :percent_met_suppressed,
        :percent_met_approximate,
        :percent_did_not_meet,
        :avg_ss,
        :std_dev_ss,
        :mean_pts_earned,
        :min_scale_score,
        :max_scale_score,
        :scale_score_25,
        :scale_score_50,
        :scale_score_75,
        :mde_building_id
      ]
    end

    # District-level rollup upsert
    create :upsert_district_rollup do
      upsert? true
      upsert_identity :unique_district_rollup

      upsert_fields [
        :total_advanced,
        :total_proficient,
        :total_partially_proficient,
        :total_not_proficient,
        :total_surpassed,
        :total_attained,
        :total_emerging_towards,
        :total_met,
        :total_did_not_meet,
        :number_assessed,
        :percent_advanced,
        :percent_proficient,
        :percent_partially_proficient,
        :percent_not_proficient,
        :percent_surpassed,
        :percent_attained,
        :percent_emerging_towards,
        :percent_met,
        :percent_met_suppressed,
        :percent_met_approximate,
        :percent_did_not_meet,
        :avg_ss,
        :std_dev_ss,
        :mean_pts_earned,
        :min_scale_score,
        :max_scale_score,
        :scale_score_25,
        :scale_score_50,
        :scale_score_75
      ]

      accept [
        :mde_district_id,
        :rollup_level,
        :school_year,
        :test_type,
        :test_population,
        :grade_content_tested,
        :subject,
        :report_category,
        :total_advanced,
        :total_proficient,
        :total_partially_proficient,
        :total_not_proficient,
        :total_surpassed,
        :total_attained,
        :total_emerging_towards,
        :total_met,
        :total_did_not_meet,
        :number_assessed,
        :percent_advanced,
        :percent_proficient,
        :percent_partially_proficient,
        :percent_not_proficient,
        :percent_surpassed,
        :percent_attained,
        :percent_emerging_towards,
        :percent_met,
        :percent_met_suppressed,
        :percent_met_approximate,
        :percent_did_not_meet,
        :avg_ss,
        :std_dev_ss,
        :mean_pts_earned,
        :min_scale_score,
        :max_scale_score,
        :scale_score_25,
        :scale_score_50,
        :scale_score_75
      ]
    end

    # ISD-level rollup upsert
    create :upsert_isd_rollup do
      upsert? true
      upsert_identity :unique_isd_rollup

      upsert_fields [
        :total_advanced,
        :total_proficient,
        :total_partially_proficient,
        :total_not_proficient,
        :total_surpassed,
        :total_attained,
        :total_emerging_towards,
        :total_met,
        :total_did_not_meet,
        :number_assessed,
        :percent_advanced,
        :percent_proficient,
        :percent_partially_proficient,
        :percent_not_proficient,
        :percent_surpassed,
        :percent_attained,
        :percent_emerging_towards,
        :percent_met,
        :percent_met_suppressed,
        :percent_met_approximate,
        :percent_did_not_meet,
        :avg_ss,
        :std_dev_ss,
        :mean_pts_earned,
        :min_scale_score,
        :max_scale_score,
        :scale_score_25,
        :scale_score_50,
        :scale_score_75
      ]

      accept [
        :mde_isd_id,
        :rollup_level,
        :school_year,
        :test_type,
        :test_population,
        :grade_content_tested,
        :subject,
        :report_category,
        :total_advanced,
        :total_proficient,
        :total_partially_proficient,
        :total_not_proficient,
        :total_surpassed,
        :total_attained,
        :total_emerging_towards,
        :total_met,
        :total_did_not_meet,
        :number_assessed,
        :percent_advanced,
        :percent_proficient,
        :percent_partially_proficient,
        :percent_not_proficient,
        :percent_surpassed,
        :percent_attained,
        :percent_emerging_towards,
        :percent_met,
        :percent_met_suppressed,
        :percent_met_approximate,
        :percent_did_not_meet,
        :avg_ss,
        :std_dev_ss,
        :mean_pts_earned,
        :min_scale_score,
        :max_scale_score,
        :scale_score_25,
        :scale_score_50,
        :scale_score_75
      ]
    end

    update :update do
      primary? true

      accept [
        :total_advanced,
        :total_proficient,
        :total_partially_proficient,
        :total_not_proficient,
        :total_surpassed,
        :total_attained,
        :total_emerging_towards,
        :total_met,
        :total_did_not_meet,
        :number_assessed,
        :percent_advanced,
        :percent_proficient,
        :percent_partially_proficient,
        :percent_not_proficient,
        :percent_surpassed,
        :percent_attained,
        :percent_emerging_towards,
        :percent_met,
        :percent_met_suppressed,
        :percent_met_approximate,
        :percent_did_not_meet,
        :avg_ss,
        :std_dev_ss,
        :mean_pts_earned,
        :min_scale_score,
        :max_scale_score,
        :scale_score_25,
        :scale_score_50,
        :scale_score_75
      ]
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

    # ── Granularity ───────────────────────────────────────────────────────────

    # Distinguishes building-level rows from pre-aggregated district and ISD rollup rows
    attribute :rollup_level, :atom do
      constraints one_of: [:building, :district, :isd]
      default :building
      allow_nil? false
      public? true
    end

    # ── Dimension Keys ────────────────────────────────────────────────────────

    # Matches AcademicYear.label (e.g. "2022-2023") — cross-tenant soft join
    attribute :school_year, :string do
      allow_nil? false
      public? true
    end

    # e.g. "M-STEP", "PSAT 8/9", "PSAT 10", "SAT"
    attribute :test_type, :string do
      allow_nil? false
      public? true
    end

    # e.g. "Tested Students", "All Students"
    attribute :test_population, :string do
      allow_nil? false
      public? true
    end

    # e.g. "03", "04", "05", "06", "07", "08", "11", "All"
    attribute :grade_content_tested, :string do
      allow_nil? false
      public? true
    end

    # ELA, Math, Science, Social Studies
    attribute :subject, :string do
      allow_nil? false
      public? true
    end

    # ESSA subgroup: "All Students", "Economically Disadvantaged",
    # "English Learners", "Students with Disabilities", etc.
    attribute :report_category, :string do
      allow_nil? false
      public? true
    end

    # ── Raw Counts (nil = MDE small-cell suppression, <10 students) ───────────

    attribute :total_advanced, :integer do
      allow_nil? true
      public? true
    end

    attribute :total_proficient, :integer do
      allow_nil? true
      public? true
    end

    attribute :total_partially_proficient, :integer do
      allow_nil? true
      public? true
    end

    attribute :total_not_proficient, :integer do
      allow_nil? true
      public? true
    end

    # SAT/PSAT performance levels (Surpassed / Attained / Emerging Towards / Met / Did Not Meet)
    attribute :total_surpassed, :integer do
      allow_nil? true
      public? true
    end

    attribute :total_attained, :integer do
      allow_nil? true
      public? true
    end

    attribute :total_emerging_towards, :integer do
      allow_nil? true
      public? true
    end

    attribute :total_met, :integer do
      allow_nil? true
      public? true
    end

    attribute :total_did_not_meet, :integer do
      allow_nil? true
      public? true
    end

    attribute :number_assessed, :integer do
      allow_nil? true
      public? true
    end

    # ── Percentages (nil when suppressed) ────────────────────────────────────

    attribute :percent_advanced, :decimal do
      allow_nil? true
      public? true
    end

    attribute :percent_proficient, :decimal do
      allow_nil? true
      public? true
    end

    attribute :percent_partially_proficient, :decimal do
      allow_nil? true
      public? true
    end

    attribute :percent_not_proficient, :decimal do
      allow_nil? true
      public? true
    end

    attribute :percent_surpassed, :decimal do
      allow_nil? true
      public? true
    end

    attribute :percent_attained, :decimal do
      allow_nil? true
      public? true
    end

    attribute :percent_emerging_towards, :decimal do
      allow_nil? true
      public? true
    end

    attribute :percent_met, :decimal do
      allow_nil? true
      public? true
    end

    # True when MDE published "*" for PercentMet — FERPA small-cell suppression
    # (cohort < 10 students). percent_met will be nil; this flag preserves the
    # distinction so the UI can display "*" and calculations can exclude the row.
    attribute :percent_met_suppressed, :boolean do
      default false
      allow_nil? false
      public? true
    end

    # True when MDE published a range value for PercentMet (Rule 2), e.g. "<=5%",
    # ">=95%", ">90%". The numeric boundary is stored in percent_met; this flag
    # signals the UI to show a light gray background indicating the value is
    # approximate, not an exact percentage.
    attribute :percent_met_approximate, :boolean do
      default false
      allow_nil? false
      public? true
    end

    attribute :percent_did_not_meet, :decimal do
      allow_nil? true
      public? true
    end

    # ── Scale Score Statistics (nil when suppressed) ──────────────────────────

    attribute :avg_ss, :decimal do
      allow_nil? true
      public? true
    end

    attribute :std_dev_ss, :decimal do
      allow_nil? true
      public? true
    end

    attribute :mean_pts_earned, :decimal do
      allow_nil? true
      public? true
    end

    attribute :min_scale_score, :decimal do
      allow_nil? true
      public? true
    end

    attribute :max_scale_score, :decimal do
      allow_nil? true
      public? true
    end

    attribute :scale_score_25, :decimal do
      allow_nil? true
      public? true
    end

    attribute :scale_score_50, :decimal do
      allow_nil? true
      public? true
    end

    attribute :scale_score_75, :decimal do
      allow_nil? true
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    # Nullable: rollup rows (district/ISD level) have no specific building
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
    # Building-level: one row per building × year × test × population × grade × subject × subgroup
    identity :unique_result, [
      :mde_building_id,
      :school_year,
      :test_type,
      :test_population,
      :grade_content_tested,
      :subject,
      :report_category
    ]

    # District-level rollup: one row per district × year × test × population × grade × subject × subgroup
    identity :unique_district_rollup, [
      :mde_district_id,
      :rollup_level,
      :school_year,
      :test_type,
      :test_population,
      :grade_content_tested,
      :subject,
      :report_category
    ]

    # ISD-level rollup: one row per ISD × year × test × population × grade × subject × subgroup
    identity :unique_isd_rollup, [
      :mde_isd_id,
      :rollup_level,
      :school_year,
      :test_type,
      :test_population,
      :grade_content_tested,
      :subject,
      :report_category
    ]
  end
end
