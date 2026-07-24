defmodule Emisint.Assessments.MdeSssComparisonGroup do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @moduledoc """
  Stores one SSS peer-group definition keyed by `comparison_code`.

  The anchor school is identified by the source rule:
  `school_code == comparison_code`.
  """

  postgres do
    table "mde_sss_comparison_groups"
    repo Emisint.Repo

    custom_indexes do
      index [:anchor_school_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:comparison_code, :anchor_school_id]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_comparison_code
      upsert_fields [:anchor_school_id]
      accept [:comparison_code, :anchor_school_id]
    end

    update :update do
      primary? true
      accept [:anchor_school_id]
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

    attribute :comparison_code, :string do
      allow_nil? false
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :anchor_school, Emisint.Assessments.MdeSssSchool do
      allow_nil? false
      attribute_writable? true
      public? true
    end

    has_many :members, Emisint.Assessments.MdeSssComparisonGroupMember do
      destination_attribute :comparison_group_id
      public? true
    end
  end

  identities do
    identity :unique_comparison_code, [:comparison_code]
  end
end
