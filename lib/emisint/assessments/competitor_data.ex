defmodule Emisint.Assessments.CompetitorData do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "competitor_data"
    repo Emisint.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :district_name,
        :mde_district_code,
        :subject,
        :grade_level,
        :proficiency_rate,
        :average_sgp,
        :student_count,
        :academic_year_label
      ]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_district_subject_grade_year

      accept [
        :district_name,
        :mde_district_code,
        :subject,
        :grade_level,
        :proficiency_rate,
        :average_sgp,
        :student_count,
        :academic_year_label
      ]
    end

    update :update do
      primary? true

      accept [
        :district_name,
        :proficiency_rate,
        :average_sgp,
        :student_count
      ]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system_admin) do
      authorize_if always()
    end

    # Public MDE reference data — any authenticated user may read it
    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :system_admin)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :district_name, :string do
      allow_nil? false
      public? true
    end

    attribute :mde_district_code, :string do
      allow_nil? false
      public? true
    end

    attribute :subject, :string do
      allow_nil? false
      public? true
    end

    # Grade level string (e.g., "3", "4", "all") — MDE aggregate data varies in representation
    attribute :grade_level, :string do
      allow_nil? false
      public? true
    end

    # Expressed as a decimal between 0 and 1 (e.g., 0.65 = 65% proficient)
    attribute :proficiency_rate, :decimal do
      allow_nil? false
      public? true
    end

    attribute :average_sgp, :decimal do
      public? true
    end

    attribute :student_count, :integer do
      public? true
    end

    attribute :academic_year_label, :string do
      allow_nil? false
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_district_subject_grade_year, [
      :mde_district_code,
      :subject,
      :grade_level,
      :academic_year_label
    ]
  end
end
