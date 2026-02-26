defmodule Emisint.Registry.Enrollment do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Registry,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "enrollments"
    repo Emisint.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :grade_level,
        :status,
        :enrolled_at,
        :exited_at,
        :student_id,
        :academic_year_id,
        :school_id
      ]
    end

    update :update do
      primary? true
      accept [:grade_level, :status, :exited_at]
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

    attribute :grade_level, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:pk, :k, :g1, :g2, :g3, :g4, :g5, :g6, :g7, :g8, :g9, :g10, :g11, :g12]
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :transferred, :withdrawn]
    end

    attribute :enrolled_at, :date do
      allow_nil? false
      public? true
    end

    attribute :exited_at, :date do
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

    belongs_to :school, Emisint.Accounts.School do
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end

  identities do
    identity :unique_enrollment, [:student_id, :academic_year_id, :school_id]
  end
end
