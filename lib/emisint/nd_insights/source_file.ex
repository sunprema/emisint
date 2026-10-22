defmodule Emisint.NdInsights.SourceFile do
  @moduledoc """
  An official ND Insights download that has been imported, identified by its
  SHA-256. `publication_version` is the `-vYYYYMMDD` stamp in the state's file
  name. `last_report` keeps the counts and any conflicts from the most recent
  import of this exact file.
  """
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.NdInsights,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "nd_insights_source_files"
    repo Emisint.Repo
  end

  actions do
    defaults [:read]

    create :register do
      accept [
        :dataset,
        :file_name,
        :publication_version,
        :sha256,
        :bytes,
        :source_url,
        :downloaded_from
      ]

      change relate_actor(:imported_by, allow_nil?: true)
    end

    update :record_run do
      accept [:last_report]
      change atomic_update(:import_count, expr(import_count + 1))
      change set_attribute(:last_imported_at, &DateTime.utc_now/0)
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system_admin) do
      authorize_if always()
    end

    # Public state data: readable by any signed-in user.
    policy action_type(:read) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :dataset, :atom do
      allow_nil? false
      public? true
      constraints one_of: Emisint.NdInsights.Parser.datasets()
    end

    attribute :file_name, :string, allow_nil?: false, public?: true
    attribute :publication_version, :string, public?: true
    attribute :sha256, :string, allow_nil?: false, public?: true
    attribute :bytes, :integer, public?: true
    attribute :source_url, :string, public?: true

    attribute :downloaded_from, :string do
      public? true
      description "How the file was obtained (page and control)."
    end

    attribute :import_count, :integer, allow_nil?: false, default: 0, public?: true
    attribute :last_report, :map, allow_nil?: false, default: %{}, public?: true
    attribute :last_imported_at, :utc_datetime_usec, public?: true

    create_timestamp :first_imported_at, public?: true
  end

  relationships do
    belongs_to :imported_by, Emisint.Accounts.User, public?: true
    has_many :results, Emisint.NdInsights.StateResult, public?: true
  end

  identities do
    identity :unique_sha256, [:sha256]
  end
end
