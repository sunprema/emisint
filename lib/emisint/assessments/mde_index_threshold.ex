defmodule Emisint.Assessments.MdeIndexThreshold do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "mde_index_thresholds"
    repo Emisint.Repo
  end

  @upsert_fields [:threshold_value]

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:school_year, :component, :threshold_value]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_component_year
      upsert_fields @upsert_fields

      accept [:school_year, :component, :threshold_value]
    end

    update :update do
      primary? true
      accept [:threshold_value]
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

    # Matches format "2024-2025"
    attribute :school_year, :string do
      allow_nil? false
      public? true
    end

    attribute :component, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :overall,
                    :growth,
                    :proficiency,
                    :graduation,
                    :el_progress,
                    :school_quality,
                    :subject_participation,
                    :el_participation
                  ]
    end

    attribute :threshold_value, :decimal do
      allow_nil? false
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_component_year, [:school_year, :component]
  end
end
