defmodule Emisint.Accounts.SchoolMembership do
  @moduledoc """
  Grants a user access to one school in their organization.

    * `:viewer`      — read only
    * `:contributor` — read, record and correct metric results and ratings
    * `:reviewer`    — read; formal review ratings arrive in a later phase

  The user's `organization_id` must equal the tenant, and the school must
  exist in the tenant.
  """
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Emisint.Improvement.Changes.InheritScope
  alias Emisint.Improvement.Checks.{CanReadSchoolData, CanWriteSchoolData}

  postgres do
    table "school_memberships"
    repo Emisint.Repo

    custom_indexes do
      index [:school_id]
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:user_id, :school_id, :role]

      change {InheritScope, from: :school_id, resource: Emisint.Accounts.School, copy: []}
      validate Emisint.Accounts.Validations.UserInTenant
    end

    destroy :destroy do
      primary? true
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system_admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if {CanReadSchoolData, via: :user}
    end

    policy action_type(:create) do
      authorize_if {CanWriteSchoolData, roles: []}
    end

    policy action_type(:destroy) do
      authorize_if {CanReadSchoolData, via: :none}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:viewer, :contributor, :reviewer]
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Emisint.Accounts.Organization do
      allow_nil? false
      public? true
    end

    belongs_to :user, Emisint.Accounts.User do
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
    identity :unique_user_school, [:user_id, :school_id]
  end
end
