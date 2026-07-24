defmodule Emisint.Reports.School.SssComparisonPdf do
  @moduledoc """
  Generates an SSS (Statistically Similar Schools) Comparison PDF for a school
  code and school year.

  Compares one anchor school against the simple (unweighted) composite of its
  SSS peer group.
  """

  @template_path "priv/typst/school/sss_comparison.typ"
  @subject_keys [
    {"ELA", :ela},
    {"Mathematics", :math},
    {"Science", :sci},
    {"Social Studies", :ss}
  ]

  require Ash.Query

  alias Emisint.Assessments.{
    MdeEntityMaster,
    MdeSatResult,
    MdeSchoolVsLeaSnapshot,
    MdeSssComparisonGroup
  }

  @spec generate_report(String.t(), String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def generate_report(school_code, year, _opts \\ []) do
    template = File.read!(Application.app_dir(:emisint, @template_path))
    data = build_data(school_code, year)
    config = Imprintor.Config.new(template, data)
    Imprintor.compile_to_pdf(config)
  end

  defp build_data(school_code, year) do
    group =
      MdeSssComparisonGroup
      |> Ash.Query.filter(comparison_code in ^code_candidates(school_code))
      |> Ash.Query.load(members: :school)
      |> Ash.read!(authorize?: false)
      |> pick_group(school_code)

    if is_nil(group) do
      raise "No SSS comparison group found for school code #{school_code}"
    else
      anchor = load_school_profile(school_code, year, fallback_name: school_code)

      peers =
        group.members
        |> Enum.map(& &1.school)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(& &1.lookup_key)
        |> Enum.reject(&(&1.school_code in code_candidates(school_code)))
        |> Enum.map(fn school ->
          load_school_profile(school.school_code, year, fallback_name: school.school_name)
        end)
        |> Enum.sort_by(& &1.name)

      scored_peers = Enum.filter(peers, & &1.has_mstep)
      sat_peers = Enum.filter(peers, & &1.has_sat)
      composite_mstep = subjects_composite(scored_peers)
      composite_sat = sat_composite(sat_peers)

      entity = load_entity_details(school_code)

      %{
        school: %{
          name: anchor.name,
          school_code: school_code,
          report_date: Date.utc_today() |> Calendar.strftime("%b %d, %Y")
        },
        school_year: year,
        entity_details: entity,
        total_peers: length(peers),
        scored_peers: length(scored_peers),
        has_any_sat: not is_nil(anchor.sat) or length(sat_peers) > 0,
        charter: %{
          mstep: Map.put(anchor.mstep, :avg, avg_floats(Map.values(anchor.mstep))),
          sat: anchor.sat || %{math: nil, ebrw: nil, all: nil}
        },
        composite: %{
          mstep: Map.put(composite_mstep, :avg, avg_floats(Map.values(composite_mstep))),
          sat: composite_sat
        },
        peers: Enum.map(peers, &peer_row/1)
      }
    end
  end

  defp load_school_profile(school_code, year, opts) do
    fallback_name = Keyword.get(opts, :fallback_name, school_code)

    snapshot =
      code_candidates(school_code)
      |> Enum.find_value(fn code ->
        MdeSchoolVsLeaSnapshot
        |> Ash.Query.for_read(:by_building_and_year, %{building_code: code, school_year: year})
        |> Ash.read_one!(authorize?: false)
      end)

    sat =
      code_candidates(school_code)
      |> Enum.find_value(fn code ->
        MdeSatResult
        |> Ash.Query.filter(
          building_code == ^code and school_year == ^year and rollup_level == :building and
            subgroup == "All Students"
        )
        |> Ash.read_one!(authorize?: false)
      end)
      |> sat_map()

    mstep =
      if snapshot do
        snapshot.subject_comparison
        |> subject_comparison_to_map()
      else
        %{ela: nil, math: nil, sci: nil, ss: nil}
      end

    %{
      name: (snapshot && snapshot.school_name) || fallback_name,
      school_code: school_code,
      mstep: mstep,
      sat: sat,
      has_mstep: not is_nil(avg_floats(Map.values(mstep))),
      has_sat: not is_nil(sat)
    }
  end

  @entity_select [
    :entity_official_name,
    :isd_code,
    :isd_official_name,
    :entity_type_name,
    :entity_county_name,
    :entity_chartering_agency_code,
    :entity_chartering_agency_name,
    :entity_authorized_grades,
    :entity_actual_grades
  ]

  defp load_entity_details(school_code) do
    record =
      MdeEntityMaster
      |> Ash.Query.filter(entity_code in ^code_candidates(school_code))
      |> Ash.Query.select(@entity_select)
      |> Ash.Query.sort(:entity_code)
      |> Ash.read!(authorize?: false)
      |> List.first()

    %{
      name: record && record.entity_official_name,
      isd_code: record && record.isd_code,
      isd_official_name: record && record.isd_official_name,
      entity_type_name: record && record.entity_type_name,
      county_name: record && record.entity_county_name,
      chartering_agency_code: record && record.entity_chartering_agency_code,
      chartering_agency_name: record && record.entity_chartering_agency_name,
      authorized_grades: record && record.entity_authorized_grades,
      actual_grades: record && record.entity_actual_grades
    }
  end

  defp subjects_composite(rows) do
    %{
      ela: mean(rows, fn r -> r.mstep.ela end),
      math: mean(rows, fn r -> r.mstep.math end),
      sci: mean(rows, fn r -> r.mstep.sci end),
      ss: mean(rows, fn r -> r.mstep.ss end)
    }
  end

  defp sat_composite(rows) do
    %{
      math: mean(rows, fn r -> r.sat && r.sat.math end),
      ebrw: mean(rows, fn r -> r.sat && r.sat.ebrw end),
      all: mean(rows, fn r -> r.sat && r.sat.all end)
    }
  end

  defp mean(rows, fun) do
    values =
      rows
      |> Enum.map(fun)
      |> Enum.reject(&is_nil/1)

    avg_floats(values)
  end

  defp peer_row(peer) do
    %{
      name: peer.name,
      school_code: peer.school_code,
      ela: peer.mstep.ela,
      math: peer.mstep.math,
      sci: peer.mstep.sci,
      ss: peer.mstep.ss,
      mstep_avg: avg_floats(Map.values(peer.mstep)),
      sat_math: peer.sat && peer.sat.math,
      sat_ebrw: peer.sat && peer.sat.ebrw,
      sat_all: peer.sat && peer.sat.all,
      has_mstep: peer.has_mstep,
      has_sat: peer.has_sat
    }
  end

  defp subject_comparison_to_map(nil), do: %{ela: nil, math: nil, sci: nil, ss: nil}

  defp subject_comparison_to_map(rows) do
    by_subject = Map.new(rows, fn row -> {row["subject"], row} end)

    Map.new(@subject_keys, fn {subject_name, key} ->
      value = by_subject |> Map.get(subject_name, %{}) |> Map.get("school_pct")
      {key, to_float(value)}
    end)
  end

  defp sat_map(nil), do: nil

  defp sat_map(row) do
    %{
      math: to_float(row.math_score_average),
      ebrw: to_float(row.ebrw_score_average),
      all: to_float(row.all_subject_score_average)
    }
  end

  defp avg_floats(values) do
    nums = values |> Enum.reject(&is_nil/1) |> Enum.map(&to_float/1) |> Enum.reject(&is_nil/1)
    if nums == [], do: nil, else: Float.round(Enum.sum(nums) / length(nums), 1)
  end

  defp pick_group([], _school_code), do: nil

  defp pick_group(groups, school_code) do
    code = school_code |> to_string() |> String.trim()
    Enum.find(groups, &(&1.comparison_code == code)) || List.first(groups)
  end

  defp code_candidates(nil), do: []

  defp code_candidates(code) do
    trimmed = to_string(code) |> String.trim()
    stripped = String.trim_leading(trimmed, "0")

    padded =
      if stripped == "" do
        nil
      else
        String.pad_leading(stripped, 5, "0")
      end

    [trimmed, stripped, padded]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp to_float(nil), do: nil
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(v) when is_integer(v), do: v * 1.0
  defp to_float(v) when is_float(v), do: v

  defp to_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> nil
    end
  end
end
