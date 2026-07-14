defmodule Emisint.Assessments.MdeSssComparisonGroupMember do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @moduledoc """
  Join rows for SSS comparison groups and member schools.
  """

  postgres do
    table "mde_sss_comparison_group_members"
    repo Emisint.Repo

    custom_indexes do
      index [:comparison_group_id]
      index [:school_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:comparison_group_id, :school_id]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_group_member
      upsert_fields []
      accept [:comparison_group_id, :school_id]
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

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :comparison_group, Emisint.Assessments.MdeSssComparisonGroup do
      allow_nil? false
      attribute_writable? true
      public? true
    end

    belongs_to :school, Emisint.Assessments.MdeSssSchool do
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end

  identities do
    identity :unique_group_member, [:comparison_group_id, :school_id]
  end
end
