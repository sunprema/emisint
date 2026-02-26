defmodule Emisint.Assessments.AssessmentResult do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "assessment_results"
    repo Emisint.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :assessment_type,
        :subject,
        :testing_window,
        :raw_score,
        :scale_score,
        :proficiency_level,
        :sgp,
        :growth_target,
        :percentile,
        :test_date,
        :source,
        :student_id,
        :academic_year_id
      ]
    end

    create :bulk_upsert do
      upsert? true
      upsert_identity :unique_assessment_per_window

      accept [
        :assessment_type,
        :subject,
        :testing_window,
        :raw_score,
        :scale_score,
        :proficiency_level,
        :sgp,
        :growth_target,
        :percentile,
        :test_date,
        :source,
        :student_id,
        :academic_year_id
      ]
    end

    update :update do
      primary? true

      accept [
        :raw_score,
        :scale_score,
        :proficiency_level,
        :sgp,
        :growth_target,
        :percentile,
        :test_date,
        :source
      ]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system_admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if actor_attribute_equals(:organization_id, :organization_id)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :emo_admin)
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_primary_key :id

    attribute :assessment_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:m_step, :psat_8_9, :psat_10, :sat, :nwea_map, :i_ready]
    end

    attribute :subject, :string do
      allow_nil? false
      public? true
    end

    attribute :testing_window, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:fall, :winter, :spring]
    end

    attribute :raw_score, :decimal do
      public? true
    end

    attribute :scale_score, :decimal do
      public? true
    end

    # Flexible string: "1"–"4" for M-STEP levels, or "proficient"/"not_proficient" for others
    attribute :proficiency_level, :string do
      public? true
    end

    # Student Growth Percentile (1–99)
    attribute :sgp, :integer do
      public? true
    end

    attribute :growth_target, :decimal do
      public? true
    end

    attribute :percentile, :integer do
      public? true
    end

    attribute :test_date, :date do
      public? true
    end

    # Origin of the data: "MiDataHub", "CSV", etc.
    attribute :source, :string do
      public? true
    end

    attribute :organization_id, :uuid do
      allow_nil? false
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :student, Emisint.Registry.Student do
      allow_nil? false
      attribute_writable? true
      public? true
    end

    belongs_to :academic_year, Emisint.Registry.AcademicYear do
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end

  identities do
    identity :unique_assessment_per_window, [
      :student_id,
      :academic_year_id,
      :assessment_type,
      :subject,
      :testing_window
    ]
  end
end
