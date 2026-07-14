defmodule Emisint.Assessments.MdeSssImporter do

  @moduledoc """
  Imports SSS (Statistically Similar Schools) peer-group files.

  Accepts CSV or tab-delimited files with three columns:
    - School Name
    - ComparisonCode
    - SchoolCode

  Rows are grouped by `comparison_code`. The anchor row is where
  `school_code == comparison_code`.

  The importer matches existing MDE import conventions:
    - bulk upserts
    - best-effort row processing (bad rows do not halt import)
    - row-level issue CSV output
  """

  require Ash.Query

  alias Emisint.Assessments.MdeSssComparisonGroup
  alias Emisint.Assessments.MdeSssComparisonGroupMember
  alias Emisint.Assessments.MdeSssSchool

  NimbleCSV.define(Emisint.Assessments.SssTsvParser, separator: "\t", escape: "\"")

  @header_map %{
    school_name: "School Name",
    comparison_code: "ComparisonCode",
    school_code: "SchoolCode"
  }

  @reason_missing_school_code "MISSING_SCHOOL_CODE"
  @reason_missing_school_name "MISSING_SCHOOL_NAME"
  @reason_no_anchor_found "NO_ANCHOR_FOUND"
  @reason_duplicate_row "DUPLICATE_ROW"

  @type issue_row :: %{
          row_number: non_neg_integer(),
          school_name: String.t() | nil,
          comparison_code: String.t() | nil,
          school_code: String.t() | nil,
          reason_code: String.t()
        }

  @spec import_file(Path.t()) :: {:ok, map()} | {:error, String.t()}
  def import_file(path) do
    with :ok <- validate_file(path) do
      rows = stream_as_maps(path) |> Enum.map(&to_row/1)

      payload = build_payload(rows)
      persist_result = persist_payload(payload)

      issues = payload.issues ++ persist_result.persistence_issues
      error_file = write_issue_csv(path, issues)

      {:ok,
       %{
         total_rows: payload.total_rows,
         records: persist_result.memberships,
         groups: persist_result.groups,
         schools: persist_result.schools,
         warnings: payload.warning_rows,
         errors: payload.failed_rows + persist_result.persistence_error_count,
         error_file: error_file
       }}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp build_payload(rows) do
    parsed =
      Enum.reduce(rows, %{clean_rows: [], issues: []}, fn row, acc ->
        cond do
          is_nil(row.school_name) ->
            issue = issue_for(row, @reason_missing_school_name)
            %{acc | issues: [issue | acc.issues]}

          is_nil(row.comparison_code) ->
            issue = issue_for(row, @reason_no_anchor_found)
            %{acc | issues: [issue | acc.issues]}

          true ->
            %{acc | clean_rows: [row | acc.clean_rows]}
        end
      end)

    grouped = Enum.group_by(parsed.clean_rows, & &1.comparison_code)

    processed =
      Enum.reduce(grouped, empty_payload(), fn {_comparison_code, group_rows}, acc ->
        group_result = process_group(group_rows)
        merge_payload(acc, group_result)
      end)

    %{
      total_rows: length(rows),
      warning_rows: processed.warning_rows,
      failed_rows: length(parsed.issues) + processed.failed_rows,
      schools_by_lookup: processed.schools_by_lookup,
      groups: processed.groups,
      memberships: processed.memberships,
      issues: Enum.reverse(parsed.issues) ++ processed.issues
    }
  end

  defp process_group(rows) do
    deduped =
      Enum.reduce(rows, %{seen: MapSet.new(), rows: [], issues: [], failed_rows: 0}, fn row,
                                                                                        acc ->
        row_key = {normalize_name(row.school_name), row.school_code}

        if MapSet.member?(acc.seen, row_key) do
          issue = issue_for(row, @reason_duplicate_row)
          %{acc | issues: [issue | acc.issues], failed_rows: acc.failed_rows + 1}
        else
          %{acc | seen: MapSet.put(acc.seen, row_key), rows: [row | acc.rows]}
        end
      end)

    rows = Enum.reverse(deduped.rows)
    comparison_code = rows |> List.first() |> then(&(&1 && &1.comparison_code))
    anchor = Enum.find(rows, &(&1.school_code == comparison_code))

    if is_nil(anchor) do
      no_anchor_issues = Enum.map(rows, &issue_for(&1, @reason_no_anchor_found))

      %{
        schools_by_lookup: %{},
        groups: %{},
        memberships: [],
        warning_rows: 0,
        failed_rows: deduped.failed_rows + length(rows),
        issues: Enum.reverse(deduped.issues) ++ no_anchor_issues
      }
    else
      base_payload =
        Enum.reduce(rows, empty_payload(), fn row, acc ->
          lookup_key = school_lookup_key(row.school_name, row.school_code)

          school_attrs = %{
            lookup_key: lookup_key,
            school_code: row.school_code,
            school_name: row.school_name,
            needs_review: is_nil(row.school_code)
          }

          issue =
            if is_nil(row.school_code) do
              issue_for(row, @reason_missing_school_code)
            else
              nil
            end

          %{
            acc
            | schools_by_lookup: Map.put(acc.schools_by_lookup, lookup_key, school_attrs),
              memberships: [
                %{comparison_code: row.comparison_code, school_lookup_key: lookup_key}
                | acc.memberships
              ],
              warning_rows: acc.warning_rows + if(is_nil(row.school_code), do: 1, else: 0),
              issues: if(is_nil(issue), do: acc.issues, else: [issue | acc.issues])
          }
        end)

      group_payload = %{
        comparison_code => %{
          anchor_school_lookup_key: school_lookup_key(anchor.school_name, anchor.school_code)
        }
      }

      %{
        base_payload
        | groups: group_payload,
          memberships: Enum.reverse(base_payload.memberships),
          issues: Enum.reverse(deduped.issues) ++ Enum.reverse(base_payload.issues),
          failed_rows: deduped.failed_rows
      }
    end
  end

  defp persist_payload(payload) do
    school_attrs = Map.values(payload.schools_by_lookup)

    {schools_ok, schools_err} =
      bulk_upsert(
        school_attrs,
        MdeSssSchool,
        :upsert,
        upsert_fields: [:school_code, :school_name, :needs_review]
      )

    school_lookup_to_id =
      MdeSssSchool
      |> Ash.Query.filter(lookup_key in ^Map.keys(payload.schools_by_lookup))
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.lookup_key, &1.id})

    group_attrs =
      payload.groups
      |> Enum.map(fn {comparison_code, group} ->
        %{
          comparison_code: comparison_code,
          anchor_school_id: Map.get(school_lookup_to_id, group.anchor_school_lookup_key)
        }
      end)
      |> Enum.reject(&is_nil(&1.anchor_school_id))

    {groups_ok, groups_err} =
      bulk_upsert(group_attrs, MdeSssComparisonGroup, :upsert, upsert_fields: [:anchor_school_id])

    comparison_code_to_id =
      MdeSssComparisonGroup
      |> Ash.Query.filter(comparison_code in ^Map.keys(payload.groups))
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.comparison_code, &1.id})

    member_attrs =
      payload.memberships
      |> Enum.map(fn member ->
        %{
          comparison_group_id: Map.get(comparison_code_to_id, member.comparison_code),
          school_id: Map.get(school_lookup_to_id, member.school_lookup_key)
        }
      end)
      |> Enum.reject(&(is_nil(&1.comparison_group_id) or is_nil(&1.school_id)))

    {members_ok, members_err} =
      bulk_upsert(member_attrs, MdeSssComparisonGroupMember, :upsert, upsert_fields: [])

    persistence_error_count = schools_err + groups_err + members_err

    %{
      schools: schools_ok,
      groups: groups_ok,
      memberships: members_ok,
      persistence_error_count: persistence_error_count,
      persistence_issues: []
    }
  end

  defp bulk_upsert([], _resource, _action, _opts), do: {0, 0}

  defp bulk_upsert(attrs, resource, action, opts) do
    result =
      Ash.bulk_create(attrs, resource, action,
        authorize?: false,
        return_errors?: true,
        upsert_fields: opts[:upsert_fields]
      )

    {length(attrs) - result.error_count, result.error_count}
  end

  defp stream_as_maps(path) do
    parser =
      if tab_delimited?(path), do: Emisint.Assessments.SssTsvParser, else: NimbleCSV.RFC4180

    File.stream!(path)
    |> parser.parse_stream(skip_headers: false)
    |> Stream.transform(nil, fn
      [first | rest], nil ->
        headers = [String.trim_leading(first, "\uFEFF") | rest]
        {[], headers}

      row, headers ->
        row_map = headers |> Enum.zip(row) |> Map.new()
        {[row_map], headers}
    end)
    |> Stream.with_index(2)
    |> Stream.map(fn {row, row_number} -> %{row_number: row_number, row: row} end)
  end

  defp to_row(%{row_number: row_number, row: row}) do
    %{
      row_number: row_number,
      school_name: nilify(fetch_column(row, @header_map.school_name)),
      comparison_code: nilify(fetch_column(row, @header_map.comparison_code)),
      school_code: nilify(fetch_column(row, @header_map.school_code))
    }
  end

  defp issue_for(row, reason_code) do
    %{
      row_number: row.row_number,
      school_name: row.school_name,
      comparison_code: row.comparison_code,
      school_code: row.school_code,
      reason_code: reason_code
    }
  end

  defp write_issue_csv(_path, []), do: nil

  defp write_issue_csv(input_path, issues) do
    rows =
      Enum.map(issues, fn issue ->
        [
          to_string(issue.row_number),
          to_string(issue.school_name || ""),
          to_string(issue.comparison_code || ""),
          to_string(issue.school_code || ""),
          to_string(issue.reason_code)
        ]
      end)

    content =
      NimbleCSV.RFC4180.dump_to_iodata([
        ["row_number", "school_name", "comparison_code", "school_code", "reason_code"] | rows
      ])

    base = Path.basename(input_path, Path.extname(input_path))
    error_path = Path.join(Path.dirname(input_path), "#{base}_errors.csv")
    File.write!(error_path, content)
    error_path
  end

  defp school_lookup_key(_school_name, school_code) when is_binary(school_code),
    do: "code:" <> String.trim(school_code)

  defp school_lookup_key(school_name, nil),
    do: "name:" <> normalize_name(school_name)

  defp normalize_name(name) do
    name
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp nilify(val) when is_binary(val) do
    case String.trim(val) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp nilify(val), do: val

  defp fetch_column(row, header) do
    Map.get(row, header) || Map.get(row, String.trim(header))
  end

  defp tab_delimited?(path) do
    case File.open(path, [:read]) do
      {:ok, io} ->
        line = IO.read(io, :line) || ""
        File.close(io)
        String.contains?(line, "\t")

      _ ->
        false
    end
  end

  defp validate_file(path) do
    if File.exists?(path), do: :ok, else: {:error, "File not found: #{path}"}
  end

  defp empty_payload do
    %{
      schools_by_lookup: %{},
      groups: %{},
      memberships: [],
      warning_rows: 0,
      failed_rows: 0,
      issues: []
    }
  end

  defp merge_payload(left, right) do
    %{
      schools_by_lookup: Map.merge(left.schools_by_lookup, right.schools_by_lookup),
      groups: Map.merge(left.groups, right.groups),
      memberships: left.memberships ++ right.memberships,
      warning_rows: left.warning_rows + right.warning_rows,
      failed_rows: left.failed_rows + right.failed_rows,
      issues: left.issues ++ right.issues
    }
  end
end
