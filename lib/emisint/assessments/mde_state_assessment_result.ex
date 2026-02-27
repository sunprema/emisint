defmodule Emisint.Assessments.MdeStateAssessmentResult do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "mde_state_assessment_results"
    repo Emisint.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
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
    belongs_to :mde_building, Emisint.Assessments.MdeBuilding do
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end

  identities do
    # Composite natural key — one row per building × year × test × population × grade × subject × subgroup
    identity :unique_result, [
      :mde_building_id,
      :school_year,
      :test_type,
      :test_population,
      :grade_content_tested,
      :subject,
      :report_category
    ]
  end
end
