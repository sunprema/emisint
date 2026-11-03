defmodule Emisint.NdInsights.Importer do
  @moduledoc """
  Imports official ND Insights CSV downloads for an explicit list of
  institutions (the Fort Yates pilot passes `["4300429212"]`).

  Per file:

    1. The file is identified by SHA-256 and registered once as a
       `SourceFile`; its `-vYYYYMMDD` stamp is the publication version.
    2. Rows for the requested institutions are parsed (`Parser`), keeping
       ranges, exact values and suppression exactly as published.
    3. Within the file, a measure published twice with identical values is
       stored once (counted as a duplicate). Published twice with different
       values — e.g. one institution ID listed under two names — it is a
       **conflict**: neither row is imported, and both are reported.
    4. Each measure is keyed by `natural_key` + publication version:
       * already stored with the same values → unchanged;
       * already stored with different values → conflict, not overwritten;
       * new → created; if an older publication had a different value it is
         reported under `changed_from_previous` (the older row is kept).

  A file whose publication version differs from one already stored for the
  same dataset, years and institutions is a revision and is refused unless
  `accept_revisions: true` is given.

  Imports only write `NdInsights` tables; school entries in `Improvement`
  are never touched. Returns `{:ok, [report]}` or `{:error, reason}`.
  """
  require Ash.Query

  import Ecto.Query, only: [from: 2]

  alias Emisint.NdInsights.{Parser, SourceFile, StateResult}

  @data_page "https://insights.nd.gov/Data"
  @value_fields [:unit, :value_state, :value, :range_low, :range_high]
  @report_sample 25

  @topic "nd_insights"

  @doc "PubSub topic broadcast after imports: `{:nd_insights_imported, institution_ids}`."
  def topic, do: @topic

  @doc """
  The topic for a LiveView session: `topic/0`, or a sub-topic
  (`"nd_insights:<suffix>"`) stored in the signed session under
  `"nd_insights_topic"`. Only tests set it (`EmisintWeb.ConnCase`), so
  concurrent tests never receive each other's import broadcasts.
  """
  def topic(%{"nd_insights_topic" => @topic <> ":" <> _ = topic}), do: topic
  def topic(_session), do: @topic

  @doc """
  Imports each file for `:institution_ids`. A file may be a path or
  `{path, original_file_name}` (uploads keep the state's file name, which
  carries the publication version and Engagement Survey area).

  Options:

    * `:institution_ids` (required) — verified InstitutionIDs to import
    * `:actor` — the importing user (recorded on the run log)
    * `:accept_revisions` — a file whose publication version differs from
      one already stored for the same dataset, years and institutions is a
      **revision**. It is refused unless this is `true`; when accepted it is
      stored beside the older publication, never over it.
    * `:topic` — PubSub topic for the broadcast, default `topic/0`

  Every file gets an `ImportRun` log entry (user, time, outcome, report),
  including refused and failed ones.
  """
  def import_files(files, opts) do
    institution_ids =
      opts |> Keyword.get(:institution_ids, []) |> Enum.map(&to_string/1) |> Enum.uniq()

    if institution_ids == [] do
      {:error, "at least one InstitutionID is required"}
    else
      reports =
        Enum.map(files, fn file ->
          {path, file_name} = normalize(file)

          result =
            try do
              import_file(
                path,
                file_name,
                institution_ids,
                opts[:actor],
                opts[:accept_revisions] == true
              )
            rescue
              e -> {:error, "import failed: " <> Exception.message(e)}
            end

          log_run(result, file_name, institution_ids, opts[:actor])

          case result do
            {:ok, report} -> report
            {:error, reason} -> %{file: file_name, error: describe_error(reason)}
          end
        end)

      imported =
        for %{created: n, institution_ids: ids} <- reports, n > 0, id <- ids, uniq: true, do: id

      if imported != [] do
        Phoenix.PubSub.broadcast(
          Emisint.PubSub,
          Keyword.get(opts, :topic, @topic),
          {:nd_insights_imported, imported}
        )
      end

      {:ok, reports}
    end
  end

  defp normalize({path, file_name}), do: {path, file_name}
  defp normalize(path), do: {path, Path.basename(path)}

  defp import_file(path, file_name, institution_ids, actor, accept_revisions?) do
    with {:ok, bytes} <- File.read(path),
         {:ok, parsed} <-
           Parser.parse_file(path, institution_ids: institution_ids, file_name: file_name) do
      sha256 = :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
      version = parsed.publication_version || "sha-" <> String.slice(sha256, 0, 12)

      # One import at a time (see `lock_imports/0`); the revision check runs
      # after the lock so it sees every import committed before this one.
      Emisint.Repo.transaction(fn ->
        lock_imports()
        prior = prior_versions(parsed, version)

        if prior != [] and not accept_revisions? do
          Emisint.Repo.rollback(
            {:revision_requires_confirmation,
             %{
               file: file_name,
               dataset: parsed.dataset,
               version: version,
               prior_versions: prior,
               sha256: sha256
             }}
          )
        end

        source_file = register(parsed, sha256, byte_size(bytes), version, actor)
        report = store(parsed, source_file, version)

        report =
          Map.merge(report, %{
            file: parsed.file_name,
            dataset: parsed.dataset,
            publication_version: version,
            prior_versions: prior,
            sha256: sha256,
            source_file_id: source_file.id,
            institution_ids: institution_ids,
            rows_read: parsed.rows_read,
            parse_errors: Enum.take(parsed.errors, @report_sample),
            parse_error_count: length(parsed.errors),
            name_mismatches: name_mismatches(parsed.observations)
          })

        source_file
        |> Ash.Changeset.for_update(:record_run, %{last_report: json_safe(report)},
          authorize?: false
        )
        |> Ash.update!(return_notifications?: true)

        report
      end)
    end
  end

  # Imports write a global (non-tenant) table and share `source_files` rows
  # (unique by SHA-256) and `state_results` rows (unique by natural key and
  # publication version). Two imports running at once could otherwise wait on
  # each other's uncommitted rows: re-uploading the same file concurrently
  # failed on the SHA-256 index, and transactions that import several files
  # (each holding its rows until commit) could deadlock (40P01). A
  # transaction-scoped advisory lock taken before any write serializes
  # imports; it is released when the transaction ends.
  @import_lock_key 7_311_400_429_212

  @doc false
  def import_lock_key, do: @import_lock_key

  defp lock_imports,
    do:
      Ecto.Adapters.SQL.query!(Emisint.Repo, "SELECT pg_advisory_xact_lock($1)", [
        @import_lock_key
      ])

  @doc """
  Other publication versions already stored for the same dataset, academic
  years and institutions as `parsed` (i.e. this file would be a revision).
  """
  def prior_versions(%{dataset: dataset, observations: observations}, version) do
    years = observations |> Enum.map(& &1.academic_year) |> Enum.uniq()
    ids = observations |> Enum.map(& &1.institution_id) |> Enum.uniq()
    prior_versions(dataset, years, ids, version)
  end

  def prior_versions(dataset, years, ids, version) do
    if years == [] or ids == [] do
      []
    else
      Emisint.Repo.all(
        from(r in "nd_insights_state_results",
          where:
            r.dataset == ^to_string(dataset) and r.academic_year in ^years and
              r.institution_id in ^ids and r.publication_version != ^version,
          distinct: true,
          select: r.publication_version
        )
      )
      |> Enum.sort()
    end
  end

  defp describe_error({:revision_requires_confirmation, %{version: v, prior_versions: prior}}),
    do:
      "this is a revised publication (v#{v}) of data already stored as v#{Enum.join(prior, ", v")}; " <>
        "confirm the revision to store it alongside the earlier publication"

  defp describe_error(reason) when is_binary(reason), do: reason
  defp describe_error(reason), do: inspect(reason)

  defp log_run(result, file_name, institution_ids, actor) do
    {outcome, attrs} =
      case result do
        {:ok, %{created: 0} = report} ->
          {:no_changes, run_attrs(report)}

        {:ok, report} ->
          {:imported, run_attrs(report)}

        {:error, {:revision_requires_confirmation, info} = reason} ->
          {:rejected,
           %{
             dataset: info.dataset,
             publication_version: info.version,
             sha256: info.sha256,
             error: describe_error(reason)
           }}

        {:error, reason} ->
          {:failed, %{error: describe_error(reason)}}
      end

    Emisint.NdInsights.ImportRun
    |> Ash.Changeset.for_create(
      :log,
      Map.merge(attrs, %{outcome: outcome, file_name: file_name, institution_ids: institution_ids}),
      actor: actor,
      authorize?: false
    )
    |> Ash.create!(return_notifications?: true)
  end

  defp run_attrs(report) do
    %{
      dataset: report.dataset,
      publication_version: report.publication_version,
      sha256: report.sha256,
      source_file_id: report.source_file_id,
      report: json_safe(Map.drop(report, [:source_file_id]))
    }
  end

  defp register(parsed, sha256, bytes, version, actor) do
    SourceFile
    |> Ash.Query.filter(sha256 == ^sha256)
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil ->
        SourceFile
        |> Ash.Changeset.for_create(
          :register,
          %{
            dataset: parsed.dataset,
            file_name: parsed.file_name,
            publication_version: version,
            sha256: sha256,
            bytes: bytes,
            source_url: @data_page,
            downloaded_from: "#{@data_page} (CSV download)"
          },
          actor: actor,
          authorize?: false
        )
        |> Ash.create!(return_notifications?: true)
        |> elem(0)

      existing ->
        existing
    end
  end

  defp store(parsed, source_file, version) do
    {unique, duplicates, conflicts} = dedupe(parsed.observations)
    keys = Enum.map(unique, & &1.natural_key)
    same_version = stored(keys, version)
    previous = latest_previous(keys, version)

    initial = %{
      created: 0,
      unchanged: 0,
      by_institution: %{},
      duplicates: duplicates,
      conflicts: conflicts,
      changed_from_previous: []
    }

    report =
      Enum.reduce(unique, initial, fn obs, acc ->
        case same_version[obs.natural_key] do
          nil ->
            create!(obs, source_file, version)
            acc = acc |> Map.update!(:created, &(&1 + 1)) |> count(obs.institution_id, :created)

            case previous[obs.natural_key] do
              %{} = old ->
                if same_values?(old, obs),
                  do: acc,
                  else:
                    Map.update!(
                      acc,
                      :changed_from_previous,
                      &[
                        %{
                          key: obs.natural_key,
                          previous_version: old.publication_version,
                          previous: values(old),
                          now: values(obs)
                        }
                        | &1
                      ]
                    )

              nil ->
                acc
            end

          existing ->
            if same_values?(existing, obs),
              do:
                acc
                |> Map.update!(:unchanged, &(&1 + 1))
                |> count(obs.institution_id, :unchanged),
              else:
                Map.update!(
                  acc,
                  :conflicts,
                  &[
                    %{
                      key: obs.natural_key,
                      reason: "stored value differs for the same publication; not overwritten",
                      stored: values(existing),
                      file: values(obs)
                    }
                    | &1
                  ]
                )
        end
      end)

    %{
      observations: length(parsed.observations),
      created: report.created,
      unchanged: report.unchanged,
      by_institution: report.by_institution,
      duplicate_count: report.duplicates,
      conflict_count: length(report.conflicts),
      conflicts: report.conflicts |> Enum.reverse() |> Enum.take(@report_sample),
      changed_from_previous_count: length(report.changed_from_previous),
      changed_from_previous:
        report.changed_from_previous |> Enum.reverse() |> Enum.take(@report_sample)
    }
  end

  # Measures published more than once in the same file. A conflict is decided
  # per source row (all measures of the same group): if any measure differs
  # between the repeated rows, none of that group's measures are imported,
  # because there is no way to tell which row is right.
  defp dedupe(observations) do
    groups = Enum.group_by(observations, & &1.natural_key)

    conflicting_rows =
      for {_key, [first | rest]} <- groups,
          not Enum.all?(rest, &same_values?(&1, first)),
          into: MapSet.new(),
          do: row_key(first)

    groups
    |> Enum.sort_by(fn {key, _} -> key end)
    |> Enum.reduce({[], 0, []}, fn {key, [first | rest] = all}, {unique, dups, conflicts} ->
      cond do
        MapSet.member?(conflicting_rows, row_key(first)) ->
          conflict = %{
            key: key,
            reason: "published more than once in this file with different values; none imported",
            rows: Enum.map(all, &%{institution_name: &1.institution_name, values: values(&1)})
          }

          {unique, dups, [conflict | conflicts]}

        true ->
          {[first | unique], dups + length(rest), conflicts}
      end
    end)
    |> then(fn {unique, dups, conflicts} -> {Enum.reverse(unique), dups, conflicts} end)
  end

  defp row_key(obs),
    do:
      Map.drop(obs, [
        :measure,
        :unit,
        :value_state,
        :value,
        :range_low,
        :range_high,
        :source_text,
        :raw_row,
        :natural_key,
        :institution_name
      ])

  # Per-institution counts, so school and state benchmark rows are reported
  # separately.
  defp count(acc, institution_id, field) do
    update_in(acc.by_institution[institution_id], fn counts ->
      Map.update(counts || %{created: 0, unchanged: 0}, field, 1, &(&1 + 1))
    end)
  end

  defp stored([], _version), do: %{}

  defp stored(keys, version) do
    StateResult
    |> Ash.Query.filter(natural_key in ^keys and publication_version == ^version)
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.natural_key, &1})
  end

  # Latest stored row per key from a *different* publication version.
  defp latest_previous([], _version), do: %{}

  defp latest_previous(keys, version) do
    StateResult
    |> Ash.Query.filter(natural_key in ^keys and publication_version != ^version)
    |> Ash.read!(authorize?: false)
    |> Enum.group_by(& &1.natural_key)
    |> Map.new(fn {key, rows} -> {key, Enum.max_by(rows, & &1.publication_version)} end)
  end

  defp create!(obs, source_file, version) do
    attrs =
      obs
      |> Map.take(
        StateResult.dimensions() ++
          [
            :unit,
            :value_state,
            :value,
            :range_low,
            :range_high,
            :source_text,
            :raw_row,
            :natural_key
          ]
      )
      |> Map.merge(%{publication_version: version, source_file_id: source_file.id})

    StateResult
    |> Ash.Changeset.for_create(:import, attrs, authorize?: false)
    |> Ash.create!(return_notifications?: true)
  end

  defp same_values?(a, b) do
    Enum.all?(@value_fields, fn field ->
      case {Map.get(a, field), Map.get(b, field)} do
        {%Decimal{} = x, %Decimal{} = y} -> Decimal.equal?(x, y)
        {x, y} -> x == y
      end
    end)
  end

  defp values(record), do: record |> Map.take(@value_fields) |> json_safe()

  # Compare the published name with the Emisint school registered for the ID
  # (any organization). Matching is by InstitutionID only; a different name
  # is reported, never used to link or unlink.
  defp name_mismatches(observations) do
    published =
      observations
      |> Enum.map(&{&1.institution_id, &1.institution_name})
      |> Enum.uniq()

    ids = published |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    registered =
      Emisint.Repo.all(
        from(s in "schools",
          where: s.state == "ND" and s.state_entity_id in ^ids,
          select: {s.state_entity_id, s.name}
        )
      )

    for {id, published_name} <- published,
        {^id, school_name} <- registered,
        published_name != school_name,
        uniq: true,
        do: %{
          institution_id: id,
          published_name: published_name,
          emisint_school_name: school_name
        }
  end

  defp json_safe(%Decimal{} = d), do: Decimal.to_string(d, :normal)
  defp json_safe(%{__struct__: _} = struct), do: struct |> Map.from_struct() |> json_safe()

  defp json_safe(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), json_safe(v)} end)

  defp json_safe(list) when is_list(list), do: Enum.map(list, &json_safe/1)

  defp json_safe(atom) when is_atom(atom) and not is_nil(atom) and not is_boolean(atom),
    do: to_string(atom)

  defp json_safe(other), do: other
end
