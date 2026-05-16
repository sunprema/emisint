defmodule Emisint.Assessments.MdeEmoContact do
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.Assessments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @moduledoc """
  Stores the MDE Open/Active EMO and Authorizer contact list — one row per
  district code mapping a PSA to its Education Service Provider /
  Management Organization (EMO) and the primary contact person at that school.

  This is a shared, non-multitenant reference table. The natural key is
  `district_code`. Soft-join to `Accounts.School.mde_district_code` in
  application queries when needed.
  """

  postgres do
    table "mde_emo_contacts"
    repo Emisint.Repo
  end

  @non_key_fields [
    :psa_official_name,
    :chartering_agency,
    :management_organization,
    :contact_name,
    :contact_phone,
    :contact_email
  ]

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:district_code | @non_key_fields]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_district_code
      upsert_fields @non_key_fields
      accept [:district_code | @non_key_fields]
    end

    update :update do
      primary? true
      accept @non_key_fields
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

    attribute :district_code, :string do
      allow_nil? false
      public? true
    end

    attribute :psa_official_name, :string, public?: true
    attribute :chartering_agency, :string, public?: true
    attribute :management_organization, :string, public?: true
    attribute :contact_name, :string, public?: true
    attribute :contact_phone, :string, public?: true
    attribute :contact_email, :string, public?: true

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_district_code, [:district_code]
  end
end
