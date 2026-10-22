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

  Imports only write `NdInsights` tables; school entries in `Improvement`
  are never touched. Returns `{:ok, [report]}` or `{:error, reason}`.
  """
  require Ash.Query

  import Ecto.Query, only: [from: 2]

  alias Emisint.NdInsights.{Parser, SourceFile, StateResult}

  @data_page "https://insights.nd.gov/Data"
  @value_fields [:unit, :value_state, :value, :range_low, :range_high]
  @report_sample 25

  def import_files(paths, opts) do
    institution_ids =
      opts |> Keyword.get(:institution_ids, []) |> Enum.map(&to_string/1) |> Enum.uniq()

    if institution_ids == [] do
      {:error, "at least one InstitutionID is required"}
    else
      reports =
        Enum.map(paths, fn path ->
          case import_file(path, institution_ids, opts[:actor]) do
            {:ok, report} -> report
            {:error, reason} -> %{file: Path.basename(path), error: reason}
          end
        end)

      {:ok, reports}
    end
  end

  defp import_file(path, institution_ids, actor) do
    with {:ok, bytes} <- File.read(path),
         {:ok, parsed} <- Parser.parse_file(path, institution_ids: institution_ids) do
      sha256 = :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
      version = parsed.publication_version || "sha-" <> String.slice(sha256, 0, 12)

      Emisint.Repo.transaction(fn ->
        source_file = register(parsed, sha256, byte_size(bytes), version, actor)
        report = store(parsed, source_file, version)

        report =
          Map.merge(report, %{
            file: parsed.file_name,
            dataset: parsed.dataset,
            publication_version: version,
            sha256: sha256,
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
      duplicates: duplicates,
      conflicts: conflicts,
      changed_from_previous: []
    }

    report =
      Enum.reduce(unique, initial, fn obs, acc ->
        case same_version[obs.natural_key] do
          nil ->
            create!(obs, source_file, version)
            acc = Map.update!(acc, :created, &(&1 + 1))

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
              do: Map.update!(acc, :unchanged, &(&1 + 1)),
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
