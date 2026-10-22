defmodule Emisint.Accounts.School do
  @moduledoc """
  A school within an organization (tenant). State-agnostic: `state` plus
  `state_entity_id` hold the state's own identifier (for North Dakota, the ND
  Insights institution ID, e.g. `"4300429212"` for Fort Yates Middle School).

  Created by seed/admin only; there is no update action in the pilot.
  """
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Emisint.Improvement.Checks.CanReadSchoolData

  postgres do
    table "schools"
    repo Emisint.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :name,
        :short_name,
        :slug,
        :state,
        :state_entity_id,
        :district_name,
        :grade_span,
        :active
      ]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system_admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if {CanReadSchoolData, via: :self}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :short_name, :string do
      public? true
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
    end

    attribute :state, :string do
      allow_nil? false
      public? true
    end

    attribute :state_entity_id, :string do
      allow_nil? false
      public? true
    end

    attribute :district_name, :string do
      public? true
    end

    attribute :grade_span, :string do
      public? true
    end

    attribute :active, :boolean do
      allow_nil? false
      default true
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Emisint.Accounts.Organization do
      allow_nil? false
      public? true
    end

    has_many :memberships, Emisint.Accounts.SchoolMembership do
      public? true
    end
  end

  identities do
    identity :unique_slug, [:slug]
    identity :unique_state_entity, [:state, :state_entity_id]
  end
end
