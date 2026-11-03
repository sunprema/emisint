defmodule Emisint.NdInsights.ImportRun do
  @moduledoc """
  One attempt to import an ND Insights file: who ran it, when, for which
  InstitutionIDs, and the outcome.

    * `:imported` — new measures were stored
    * `:no_changes` — every measure was already stored (a repeated upload)
    * `:rejected` — refused before writing, e.g. an unconfirmed revision
    * `:failed` — the file could not be read or validated

  Entries are append-only; `report` keeps the importer's counts, conflicts and
  changes from the previous publication.
  """
  use Ash.Resource,
    otp_app: :emisint,
    domain: Emisint.NdInsights,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "nd_insights_import_runs"
    repo Emisint.Repo
  end

  actions do
    defaults [:read]

    create :log do
      accept [
        :outcome,
        :file_name,
        :dataset,
        :publication_version,
        :sha256,
        :institution_ids,
        :report,
        :error,
        :source_file_id
      ]

      change relate_actor(:imported_by, allow_nil?: true)
    end

    read :recent do
      prepare build(sort: [ran_at: :desc], limit: 25, load: [:imported_by])
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system_admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :outcome, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:imported, :no_changes, :rejected, :failed]
    end

    attribute :file_name, :string, allow_nil?: false, public?: true

    attribute :dataset, :atom do
      public? true
      constraints one_of: Emisint.NdInsights.Parser.datasets()
    end

    attribute :publication_version, :string, public?: true
    attribute :sha256, :string, public?: true

    attribute :institution_ids, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :report, :map, allow_nil?: false, default: %{}, public?: true
    attribute :error, :string, public?: true

    create_timestamp :ran_at, public?: true
  end

  relationships do
    belongs_to :imported_by, Emisint.Accounts.User, public?: true
    belongs_to :source_file, Emisint.NdInsights.SourceFile, public?: true
  end
end
