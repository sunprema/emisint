defmodule Emisint.Assessments.MdeDistrictSnapshot do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "mde_district_snapshots"
    repo Emisint.Repo

    custom_indexes do
      index [:school_year]
      index [:district_code, :school_year]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      primary? true
      upsert? true
      upsert_identity :unique_district_year

      accept [
        :district_code,
        :school_year,
        :district_name,
        :entity_type,
        :isd_name,
        :buildings,
        :total_assessed,
        :ela_pct,
        :math_pct,
        :avg_total_proficient,
        :all_subjects,
        :grade_breakdown,
        :proficiency_dist
      ]

      upsert_fields [
        :district_name,
        :entity_type,
        :isd_name,
        :buildings,
        :total_assessed,
        :ela_pct,
        :math_pct,
        :avg_total_proficient,
        :all_subjects,
        :grade_breakdown,
        :proficiency_dist
      ]
    end

    read :by_year do
      argument :school_year, :string, allow_nil?: false
      filter expr(school_year == ^arg(:school_year))
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

    attribute :district_code, :string do
      allow_nil? false
      public? true
    end

    attribute :school_year, :string do
      allow_nil? false
      public? true
    end

    attribute :district_name, :string do
      public? true
    end

    attribute :entity_type, :string do
      public? true
    end

    attribute :isd_name, :string do
      public? true
    end

    attribute :buildings, :integer do
      public? true
      default 0
    end

    attribute :total_assessed, :integer do
      public? true
      default 0
    end

    attribute :ela_pct, :float do
      public? true
    end

    attribute :math_pct, :float do
      public? true
    end

    attribute :avg_total_proficient, :float do
      public? true
    end

    attribute :all_subjects, :map do
      public? true
    end

    attribute :grade_breakdown, {:array, :map} do
      public? true
    end

    attribute :proficiency_dist, :map do
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_district_year, [:district_code, :school_year]
  end
end
