defmodule Emisint.Compliance.Schedule71Goal do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Compliance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshPaperTrail.Resource]

  postgres do
    table "schedule71_goals"
    repo Emisint.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :title,
        :goal_type,
        :subject,
        :grade_levels,
        :testing_window,
        :assessment_type,
        :target_value,
        :comparison_operator,
        :exceeds_threshold,
        :approaching_threshold,
        :subgroup,
        :school_id,
        :charter_contract_id
      ]
    end

    update :update do
      primary? true

      accept [
        :title,
        :grade_levels,
        :testing_window,
        :assessment_type,
        :target_value,
        :comparison_operator,
        :exceeds_threshold,
        :approaching_threshold,
        :subgroup,
        :charter_contract_id
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

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :goal_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:proficiency_threshold, :sgp_median, :outperform_district, :growth_target]
    end

    attribute :subject, :string do
      allow_nil? false
      public? true
    end

    # Grade level strings matching Enrollment.grade_level atom names (e.g. "g3", "g4", "g5")
    attribute :grade_levels, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :testing_window, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:fall, :winter, :spring]
    end

    # When nil, all assessment types for the subject/window are included
    attribute :assessment_type, :atom do
      public? true
      constraints one_of: [:m_step, :psat_8_9, :psat_10, :sat, :nwea_map, :i_ready]
    end

    attribute :target_value, :decimal do
      allow_nil? false
      public? true
    end

    attribute :comparison_operator, :atom do
      allow_nil? false
      default :gte
      public? true
      constraints one_of: [:gte, :lte, :gt, :lt, :eq]
    end

    # Value at which the goal is considered "exceeded" (more than just "met")
    attribute :exceeds_threshold, :decimal do
      public? true
    end

    # Value at which the goal is considered "approaching" (below target but trending up)
    attribute :approaching_threshold, :decimal do
      public? true
    end

    # nil / :all = all students; specific atom = filter to that ESSA subgroup
    attribute :subgroup, :atom do
      public? true
      constraints one_of: [:all, :economically_disadvantaged, :english_learner, :special_education]
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

    belongs_to :charter_contract, Emisint.Compliance.CharterContract do
      allow_nil? true
      attribute_writable? true
      public? true
    end
  end

  paper_trail do
    change_tracking_mode :changes_only
    store_action_name? true
    attributes_as_attributes [:organization_id]
  end
end
