defmodule Emisint.NdInsights.UploadPreview do
  @moduledoc """
  Validates an uploaded ND Insights CSV and describes what importing it would
  do, without writing anything.

  * Statewide files are accepted with their original headers. The dataset,
    academic years and publication version are detected from the file.
  * Schools are matched only by **verified InstitutionID**: the state ID of a
    school registered in Emisint (`schools.state = 'ND'`). Names are compared
    and a mismatch is reported, never used to match. Nothing is hardcoded.
  * For the registered schools found in the file, the rows are parsed to
    report per-school measure counts, validation errors, how many measures
    are new versus already stored, and whether the file is a **revision** of
    a publication already stored (which needs explicit confirmation).
  """
  import Ecto.Query, only: [from: 2]

  alias Emisint.NdInsights.{Benchmark, Importer, Parser}

  @error_sample 10

  @doc """
  Describes `path` without writing anything.

  Pass `institution_ids:` to consider only those registered schools (the
  import UI passes the ND First pilot schools); by default every registered
  ND school is considered. Pass `benchmark?: true` to describe the file's
  "State of North Dakota" rows (`Emisint.NdInsights.Benchmark`) separately
  under `:benchmark`.
  """
  def build(path, file_name, opts \\ []) do
    with {:ok, scan} <- Parser.scan_file(path, file_name),
         {:ok, bytes} <- File.read(path) do
      sha256 = :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
      version = scan.publication_version || "sha-" <> String.slice(sha256, 0, 12)
      registered = registered_schools(Keyword.get(opts, :institution_ids))

      in_file =
        for {id, school} <- registered, inst = scan.institutions[id], inst != nil do
          published = inst.names |> MapSet.delete(nil) |> Enum.sort()

          %{
            institution_id: id,
            emisint_names: school.names,
            organizations: school.organizations,
            published_names: published,
            source_rows: inst.rows,
            name_matches?: Enum.any?(school.names, &(&1 in published))
          }
        end
        |> Enum.sort_by(&hd(&1.emisint_names))

      ids = Enum.map(in_file, & &1.institution_id)
      {per_school, totals} = dry_run(path, file_name, ids, version)
      benchmark = if opts[:benchmark?], do: benchmark(scan, path, file_name, version)
      benchmark_ids = if benchmark[:usable?], do: [Benchmark.state_id()], else: []

      {:ok,
       %{
         file_name: file_name,
         dataset: scan.dataset,
         publication_version: version,
         version_from_file_name?: scan.publication_version != nil,
         sha256: sha256,
         bytes: byte_size(bytes),
         rows_read: scan.rows_read,
         years: scan.years,
         institution_count: map_size(scan.institutions),
         already_imported?: already_imported?(sha256),
         schools: Enum.map(in_file, &Map.merge(&1, Map.get(per_school, &1.institution_id, %{}))),
         registered_not_in_file:
           for(
             {id, s} <- registered,
             not Map.has_key?(scan.institutions, id),
             do: %{institution_id: id, emisint_names: s.names}
           ),
         prior_versions:
           Importer.prior_versions(scan.dataset, scan.years, ids ++ benchmark_ids, version),
         totals: totals,
         benchmark: benchmark
       }}
    end
  end

  # The file's statewide rows: absent, present under another name (not used),
  # or usable with their new / already-stored counts.
  defp benchmark(scan, path, file_name, version) do
    id = Benchmark.state_id()

    case scan.institutions[id] do
      nil ->
        %{present?: false, usable?: false, institution_id: id}

      inst ->
        names = inst.names |> MapSet.delete(nil) |> Enum.sort()
        usable? = Benchmark.state_name() in names

        {counts, _totals} =
          if usable?, do: dry_run(path, file_name, [id], version), else: {%{}, nil}

        Map.merge(
          %{present?: true, usable?: usable?, institution_id: id, published_names: names},
          Map.get(counts, id, %{measures: 0, already_stored: 0, years: []})
        )
    end
  end

  # Parse the registered schools' rows and compare with what is stored.
  defp dry_run(_path, _file_name, [], _version),
    do: {%{}, %{measures: 0, new: 0, already_stored: 0, errors: 0}}

  defp dry_run(path, file_name, ids, version) do
    {:ok, parsed} = Parser.parse_file(path, institution_ids: ids, file_name: file_name)
    keys = Enum.map(parsed.observations, & &1.natural_key)

    stored =
      Emisint.Repo.all(
        from(r in "nd_insights_state_results",
          where: r.natural_key in ^keys and r.publication_version == ^version,
          select: r.natural_key
        )
      )
      |> MapSet.new()

    per_school =
      parsed.observations
      |> Enum.group_by(& &1.institution_id)
      |> Map.new(fn {id, obs} ->
        {id,
         %{
           measures: length(obs),
           already_stored: Enum.count(obs, &MapSet.member?(stored, &1.natural_key)),
           years: obs |> Enum.map(& &1.academic_year) |> Enum.uniq() |> Enum.sort()
         }}
      end)

    totals = %{
      measures: length(parsed.observations),
      new: Enum.count(parsed.observations, &(not MapSet.member?(stored, &1.natural_key))),
      already_stored: MapSet.size(stored),
      errors: length(parsed.errors),
      error_sample: Enum.take(parsed.errors, @error_sample)
    }

    {per_school, totals}
  end

  defp already_imported?(sha256) do
    Emisint.Repo.exists?(from(f in "nd_insights_source_files", where: f.sha256 == ^sha256))
  end

  @doc """
  ND schools registered in any organization, keyed by state InstitutionID;
  limited to `institution_ids` when given.
  """
  def registered_schools(institution_ids \\ nil)

  def registered_schools(ids) when is_list(ids), do: Map.take(registered_schools(nil), ids)

  def registered_schools(nil) do
    Emisint.Repo.all(
      from(s in "schools",
        join: o in "organizations",
        on: o.id == s.organization_id,
        where: s.state == "ND" and not is_nil(s.state_entity_id),
        select: {s.state_entity_id, s.name, o.name}
      )
    )
    |> Enum.group_by(&elem(&1, 0))
    |> Map.new(fn {id, rows} ->
      {id,
       %{
         names: rows |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort(),
         organizations: rows |> Enum.map(&elem(&1, 2)) |> Enum.uniq() |> Enum.sort()
       }}
    end)
  end
end
