defmodule Emisint.Assessments.MdeSssSchool do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @moduledoc """
  Canonical school records used by the SSS importer.

  `lookup_key` is the stable upsert key:
  - `code:<school_code>` when a code is present
  - `name:<normalized_school_name>` when code is missing

  This allows idempotent imports while still retaining schools that arrive
  without a code (`needs_review = true`).
  """

  postgres do
    table "mde_sss_schools"
    repo Emisint.Repo

    custom_indexes do
      index [:school_code]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:lookup_key, :school_code, :school_name, :needs_review]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_lookup_key
      upsert_fields [:school_code, :school_name, :needs_review]
      accept [:lookup_key, :school_code, :school_name, :needs_review]
    end

    update :update do
      primary? true
      accept [:school_code, :school_name, :needs_review]
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

    attribute :lookup_key, :string do
      allow_nil? false
      public? true
    end

    attribute :school_code, :string do
      allow_nil? true
      public? true
    end

    attribute :school_name, :string do
      allow_nil? false
      public? true
    end

    attribute :needs_review, :boolean do
      allow_nil? false
      default false
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :anchored_comparison_groups, Emisint.Assessments.MdeSssComparisonGroup do
      destination_attribute :anchor_school_id
      public? true
    end

    has_many :comparison_group_memberships, Emisint.Assessments.MdeSssComparisonGroupMember do
      destination_attribute :school_id
      public? true
    end
  end

  identities do
    identity :unique_lookup_key, [:lookup_key]
  end
end
