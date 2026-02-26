defmodule Emisint.Analytics.PerformanceSnapshot do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Analytics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "performance_snapshots"
    repo Emisint.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :snapshot_type,
        :subject,
        :grade_level,
        :subgroup,
        :testing_window,
        :proficiency_rate,
        :average_sgp,
        :median_sgp,
        :student_count,
        :school_id,
        :academic_year_id
      ]
    end

    # Idempotent upsert — called by SnapshotRefreshWorker
    create :upsert do
      upsert? true
      upsert_identity :unique_school_year_snapshot

      accept [
        :snapshot_type,
        :subject,
        :grade_level,
        :subgroup,
        :testing_window,
        :proficiency_rate,
        :average_sgp,
        :median_sgp,
        :student_count,
        :school_id,
        :academic_year_id
      ]
    end

    update :update do
      primary? true
      accept [:proficiency_rate, :average_sgp, :median_sgp, :student_count]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system_admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if actor_present()
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

    # :school_wide = all grades/subgroups; :by_grade = per grade; :by_subgroup = per ESSA group
    attribute :snapshot_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:school_wide, :by_grade, :by_subgroup]
    end

    attribute :subject, :string do
      allow_nil? false
      public? true
    end

    # "all" for school-wide snapshots; grade string (e.g. "g5") for per-grade
    attribute :grade_level, :string do
      allow_nil? false
      default "all"
      public? true
    end

    attribute :subgroup, :atom do
      allow_nil? false
      default :all
      public? true

      constraints one_of: [
                    :all,
                    :economically_disadvantaged,
                    :english_learner,
                    :special_education
                  ]
    end

    attribute :testing_window, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:fall, :winter, :spring]
    end

    attribute :proficiency_rate, :decimal do
      public? true
    end

    attribute :average_sgp, :decimal do
      public? true
    end

    attribute :median_sgp, :decimal do
      public? true
    end

    attribute :student_count, :integer do
      allow_nil? false
      default 0
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
    belongs_to :school, Emisint.Accounts.School do
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
    identity :unique_school_year_snapshot, [
      :school_id,
      :academic_year_id,
      :snapshot_type,
      :subject,
      :grade_level,
      :subgroup,
      :testing_window
    ]
  end
end
