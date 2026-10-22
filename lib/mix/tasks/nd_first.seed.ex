defmodule Mix.Tasks.NdFirst.Seed do
  @shortdoc "Seeds ND First pilot definitions (Fort Yates) into an explicit organization"

  @moduledoc """
  Seeds the Fort Yates Middle School goal plan, metrics, reporting periods and
  annual assessment goals, then imports the historical workbook ratings
  (Spr '26, Sum '26). Idempotent: existing records are never overwritten and
  differences are reported as drift.

      mix nd_first.seed --organization-id <uuid> [--actor-email <email>] [--skip-workbook-ratings]

  Development/test only — uses or creates the "ND First Pilot — Development"
  organization plus demo users and memberships:

      mix nd_first.seed --dev

  ## Options

    * `--organization-id` — existing organization to seed into (required unless `--dev`)
    * `--actor-email` — user recorded as the importer of workbook ratings
    * `--skip-workbook-ratings` — seed definitions only
    * `--dev` — use the development organization (refused outside dev/test)
  """
  use Mix.Task

  require Ash.Query

  alias Emisint.Improvement.Seeds

  @requirements ["app.start"]
  @switches [
    organization_id: :string,
    actor_email: :string,
    skip_workbook_ratings: :boolean,
    dev: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [], do: Mix.raise("Unknown options: #{inspect(invalid)}")

    {org_id, dev?} = organization(opts)
    actor = actor(opts[:actor_email])

    case Seeds.run(org_id, actor: actor, workbook_ratings?: !opts[:skip_workbook_ratings]) do
      {:ok, report} ->
        print("Definitions and workbook ratings", report)

        if dev? do
          org = Ash.get!(Emisint.Accounts.Organization, org_id, authorize?: false)

          print(
            "Dev users and memberships (password: #{Seeds.dev_password()})",
            Seeds.ensure_dev_users!(org)
          )
        end

      {:error, message} ->
        Mix.raise(message)
    end
  end

  defp organization(opts) do
    case {opts[:organization_id], opts[:dev]} do
      {nil, true} -> {Seeds.ensure_dev_organization!().id, true}
      {id, nil} when is_binary(id) -> {id, false}
      {_id, true} -> Mix.raise("Pass either --organization-id or --dev, not both")
      _ -> Mix.raise("An explicit --organization-id is required (or --dev in development)")
    end
  end

  defp actor(nil), do: nil

  defp actor(email) do
    case Ash.read_one(Ash.Query.filter(Emisint.Accounts.User, email == ^email), authorize?: false) do
      {:ok, %{} = user} -> user
      _ -> Mix.raise("No user with email #{email}")
    end
  end

  defp print(title, report) do
    Mix.shell().info("""
    #{title}
      created:   #{length(report.created)}
      unchanged: #{length(report.unchanged)}
      renamed:   #{length(report.renamed)}
      drift:     #{length(report.drift)}
    """)

    for label <- report.renamed do
      Mix.shell().info("  RENAMED in place #{label}")
    end

    for %{record: record, fields: fields} <- report.drift do
      Mix.shell().info("  DRIFT (left untouched) #{record}: #{inspect(fields)}")
    end
  end
end
