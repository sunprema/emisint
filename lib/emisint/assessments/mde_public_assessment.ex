defmodule Emisint.Assessments.MdePublicAssessment do
  @moduledoc """
  Read-only Ash resource backed by an MDE public state assessment CSV file.

  Covers M-STEP, PSAT, and SAT aggregate results published by the Michigan
  Department of Education. Each row represents one aggregation slice:
  a unique combination of school year, building, grade, subject, and
  report category (e.g., "All Students", "Economically Disadvantaged").

  The CSV path defaults to `priv/data/mde_assessment_results.csv`.
  Update the `file` option in the `csv` block to point at your actual file.

  Note: MDE suppresses cells with fewer than 10 students — all numeric
  columns are nullable to handle those empty values gracefully.
  """

  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshCsv.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  csv do
    # Update this path to your actual MDE CSV file location
    file "priv/data/mde_assessment_results.csv"
    header? true

    columns [
      :school_year,
      :test_type,
      :test_population,
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
      :mistem_code,
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
      :scale_score_75
    ]
  end

  actions do
    defaults [:read]
  end

  policies do
    bypass actor_attribute_equals(:role, :system_admin) do
      authorize_if always()
    end

    # MDE data is public — any authenticated user may read it
    policy action_type(:read) do
      authorize_if actor_present()
    end
  end

  attributes do
    # Synthetic primary key — not stored in the CSV; generated per read.
    # Use filters/identities rather than get-by-id for stable lookups.
    uuid_primary_key :id

    # ── Identification & Geography ──────────────────────────────────────────

    attribute :school_year, :string do
      public? true
    end

    attribute :test_type, :string do
      public? true
    end

    attribute :test_population, :string do
      public? true
    end

    attribute :isd_code, :string do
      public? true
    end

    attribute :isd_name, :string do
      public? true
    end

    attribute :district_code, :string do
      public? true
    end

    attribute :district_name, :string do
      public? true
    end

    attribute :building_code, :string do
      public? true
    end

    attribute :building_name, :string do
      public? true
    end

    attribute :county_code, :string do
      public? true
    end

    attribute :county_name, :string do
      public? true
    end

    attribute :entity_type, :string do
      public? true
    end

    attribute :school_level, :string do
      public? true
    end

    attribute :locale, :string do
      public? true
    end

    attribute :mistem_name, :string do
      public? true
    end

    attribute :mistem_code, :string do
      public? true
    end

    # ── Test Dimensions ──────────────────────────────────────────────────────

    attribute :grade_content_tested, :string do
      public? true
    end

    attribute :subject, :string do
      public? true
    end

    attribute :report_category, :string do
      public? true
    end

    # ── Raw Counts (nil when MDE suppresses small-cell data) ─────────────────

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
  end
end
