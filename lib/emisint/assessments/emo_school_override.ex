defmodule Emisint.Assessments.EmoSchoolOverride do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @moduledoc """
  Manual add/remove overrides on top of the MdeEmoContact-derived school list
  for a management organization (ESP Portfolio). A row with `action: :add`
  includes an entity that district-code matching wouldn't otherwise surface;
  a row with `action: :remove` excludes one that district-code matching
  would otherwise include.

  This is a shared, non-multitenant, global override — it changes what every
  org using the app sees for that management organization, matching how the
  rest of the Assessments domain (MdeEmoContact, MdeEntityMaster, etc.) is
  shared reference data rather than tenant-scoped.

  Soft-joined to `MdeEntityMaster.entity_code` and matched against
  `MdeEmoContact.management_organization` by string equality in application
  queries — see `Emisint.Assessments.EmoPortfolio.resolve_schools/1`.
  """

  postgres do
    table "emo_school_overrides"
    repo Emisint.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      primary? true
      upsert? true
      upsert_identity :unique_override
      upsert_fields [:action]
      accept [:management_organization, :entity_code, :action]
    end

    read :by_management_organization do
      argument :management_organization, :string, allow_nil?: false
      filter expr(management_organization == ^arg(:management_organization))
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

    attribute :management_organization, :string do
      allow_nil? false
      public? true
    end

    attribute :entity_code, :string do
      allow_nil? false
      public? true
    end

    attribute :action, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:add, :remove]
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_override, [:management_organization, :entity_code]
  end
end
