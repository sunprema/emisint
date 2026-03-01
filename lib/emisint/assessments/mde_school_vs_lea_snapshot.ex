defmodule Emisint.Assessments.MdeSchoolVsLeaSnapshot do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "mde_school_vs_lea_snapshots"
    repo Emisint.Repo

    custom_indexes do
      index [:school_year]
      index [:building_code, :school_year]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      primary? true
      upsert? true
      upsert_identity :unique_building_year

      accept [
        :building_code,
        :school_year,
        :school_name,
        :lea_district_code,
        :lea_district_name,
        :above_lea,
        :below_lea,
        :above_state,
        :grades_compared,
        :no_lea_found,
        :no_results,
        :no_lea_results,
        :no_state_results,
        :subject_comparison,
        :all_subjects_avg,
        :grade_breakdown
      ]

      upsert_fields [
        :school_name,
        :lea_district_code,
        :lea_district_name,
        :above_lea,
        :below_lea,
        :above_state,
        :grades_compared,
        :no_lea_found,
        :no_results,
        :no_lea_results,
        :no_state_results,
        :subject_comparison,
        :all_subjects_avg,
        :grade_breakdown
      ]
    end

    read :by_building_and_year do
      argument :building_code, :string, allow_nil?: false
      argument :school_year, :string, allow_nil?: false
      get? true
      filter expr(building_code == ^arg(:building_code) and school_year == ^arg(:school_year))
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
      authorize_if actor_attribute_equals(:role, :system_admin)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :building_code, :string do
      allow_nil? false
      public? true
    end

    attribute :school_year, :string do
      allow_nil? false
      public? true
    end

    attribute :school_name, :string do
      public? true
    end

    attribute :lea_district_code, :string do
      public? true
    end

    attribute :lea_district_name, :string do
      public? true
    end

    attribute :above_lea, :integer do
      public? true
      default 0
    end

    attribute :below_lea, :integer do
      public? true
      default 0
    end

    attribute :above_state, :integer do
      public? true
      default 0
    end

    attribute :grades_compared, :integer do
      public? true
      default 0
    end

    attribute :no_lea_found, :boolean do
      public? true
      default false
    end

    attribute :no_results, :boolean do
      public? true
      default false
    end

    attribute :no_lea_results, :boolean do
      public? true
      default false
    end

    attribute :no_state_results, :boolean do
      public? true
      default false
    end

    attribute :subject_comparison, {:array, :map} do
      public? true
    end

    attribute :all_subjects_avg, :map do
      public? true
    end

    attribute :grade_breakdown, {:array, :map} do
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_building_year, [:building_code, :school_year]
  end
end
