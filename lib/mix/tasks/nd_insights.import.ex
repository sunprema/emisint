defmodule Mix.Tasks.NdInsights.Import do
  @shortdoc "Imports official ND Insights CSV downloads for explicit institutions"

  @moduledoc """
  Imports ND Insights CSVs (from https://insights.nd.gov/Data) for the given
  InstitutionIDs. Re-running with the same files creates nothing; values that
  differ from what is stored are reported as conflicts and never overwritten.

      mix nd_insights.import --institution-id 4300429212 references/nd_insights/*.csv
      mix nd_insights.import --institution-id 4300429212 --actor-email admin@example.com FILE...

  `--institution-id` is required and may be repeated.
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(argv) do
    {opts, files, invalid} =
      OptionParser.parse(argv, strict: [institution_id: :keep, actor_email: :string])

    if invalid != [], do: Mix.raise("Unknown options: #{inspect(invalid)}")
    if files == [], do: Mix.raise("Pass one or more Insights CSV files.")

    ids = Keyword.get_values(opts, :institution_id)
    actor = opts[:actor_email] && find_user!(opts[:actor_email])

    case Emisint.NdInsights.Importer.import_files(files, institution_ids: ids, actor: actor) do
      {:ok, reports} -> Enum.each(reports, &print/1)
      {:error, reason} -> Mix.raise(reason)
    end
  end

  defp find_user!(email) do
    require Ash.Query

    case Emisint.Accounts.User
         |> Ash.Query.filter(email == ^email)
         |> Ash.read_one(authorize?: false) do
      {:ok, %{} = user} -> user
      _ -> Mix.raise("No user with email #{email}")
    end
  end

  defp print(%{error: reason, file: file}), do: Mix.shell().error("#{file}: #{reason}")

  defp print(report) do
    Mix.shell().info("""
    #{report.file} (#{report.dataset}, v#{report.publication_version})
      rows read: #{report.rows_read}   measures for #{Enum.join(report.institution_ids, ", ")}: #{report.observations}
      created: #{report.created}   unchanged: #{report.unchanged}   duplicates: #{report.duplicate_count}
      conflicts: #{report.conflict_count}   changed from previous publication: #{report.changed_from_previous_count}
      parse errors: #{report.parse_error_count}   name mismatches: #{length(report.name_mismatches)}\
    """)

    for c <- report.conflicts, do: Mix.shell().info("  CONFLICT #{c.key}: #{c.reason}")

    for c <- report.changed_from_previous,
        do: Mix.shell().info("  CHANGED #{c.key} (was v#{c.previous_version})")

    for e <- report.parse_errors,
        do: Mix.shell().info("  PARSE line #{e.line} #{e.measure}: #{e.message}")

    for m <- report.name_mismatches,
        do:
          Mix.shell().info(
            "  NAME #{m.institution_id}: published “#{m.published_name}”, Emisint “#{m.emisint_school_name}”"
          )
  end
end
