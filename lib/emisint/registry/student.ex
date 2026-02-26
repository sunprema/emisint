defmodule Emisint.Registry.Student do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Registry,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "students"
    repo Emisint.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :uic,
        :first_name,
        :last_name,
        :date_of_birth,
        :gender,
        :active,
        :economically_disadvantaged,
        :english_learner,
        :special_education
      ]
    end

    create :bulk_upsert do
      upsert? true
      upsert_identity :unique_uic_per_org

      accept [
        :uic,
        :first_name,
        :last_name,
        :date_of_birth,
        :gender,
        :active,
        :economically_disadvantaged,
        :english_learner,
        :special_education
      ]
    end

    update :update do
      primary? true

      accept [
        :first_name,
        :last_name,
        :date_of_birth,
        :gender,
        :active,
        :economically_disadvantaged,
        :english_learner,
        :special_education
      ]
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

    attribute :uic, :string do
      allow_nil? false
      public? true
    end

    attribute :first_name, :string do
      allow_nil? false
      public? true
    end

    attribute :last_name, :string do
      allow_nil? false
      public? true
    end

    attribute :date_of_birth, :date do
      public? true
    end

    attribute :gender, :atom do
      public? true
      constraints one_of: [:male, :female, :nonbinary, :undisclosed]
    end

    attribute :active, :boolean do
      default true
      public? true
    end

    # ESSA subgroup flags — power the subgroup heatmaps
    attribute :economically_disadvantaged, :boolean do
      default false
      public? true
    end

    attribute :english_learner, :boolean do
      default false
      public? true
    end

    attribute :special_education, :boolean do
      default false
      public? true
    end

    attribute :organization_id, :uuid do
      allow_nil? false
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_uic_per_org, [:uic, :organization_id]
  end
end
