defmodule Emisint.Reports.Portfolio.PortfolioPdf do
  @moduledoc """
  Generates a Portfolio Overview PDF for a chartering agency.

  Includes M-STEP vs LEA comparison, SAT vs LEA comparison, and school directory.
  """

  @template_path "priv/typst/portfolio/portfolio.typ"

  import Ecto.Query, only: [from: 2]

  require Ash.Query

  alias Emisint.Assessments.MdeEntityMaster
  alias Emisint.Repo

  def generate_report(agency_code, year, _opts \\ []) do
    template = File.read!(Application.app_dir(:emisint, @template_path))
    data = build_data(agency_code, year)
    config = Imprintor.Config.new(template, data)
    Imprintor.compile_to_pdf(config)
  end

  # ---------------------------------------------------------------------------
  # Data assembly
  # ---------------------------------------------------------------------------

  defp build_data(agency_code, year) do
    schools = load_schools(agency_code)
    building_codes = schools |> Enum.map(& &1.entity_code) |> Enum.reject(&is_nil/1)

    agency_task = Task.async(fn -> load_agency_info(agency_code, schools) end)
    mstep_task = Task.async(fn -> load_mstep_stats(building_codes, year) end)
    sat_task = Task.async(fn -> load_sat_stats(building_codes, year) end)

    agency_info = Task.await(agency_task)
    mstep_raw = Task.await(mstep_task)
    sat_raw = Task.await(sat_task)

    %{
      agency: agency_info,
      school_year: year,
      report_date: Date.utc_today() |> Calendar.strftime("%b %d, %Y"),
      schools: format_schools(schools),
      mstep: format_section(mstep_raw, :mstep),
      sat: format_section(sat_raw, :sat)
    }
  end

  # ---------------------------------------------------------------------------
  # Data loaders
  # ---------------------------------------------------------------------------

  defp load_schools(agency_code) do
    MdeEntityMaster
    |> Ash.Query.select([
      :entity_code,
      :entity_official_name,
      :district_code,
      :entity_county_name,
      :entity_actual_grades,
      :entity_authorized_grades
    ])
    |> Ash.Query.filter(
      entity_chartering_agency_code == ^agency_code and entity_status == "Open-Active"
    )
    |> Ash.Query.sort(entity_official_name: :asc)
    |> Ash.read!(authorize?: false)
  rescue
    _ -> []
  end

  defp load_agency_info(agency_code, schools) do
    sample =
      MdeEntityMaster
      |> Ash.Query.select([:entity_chartering_agency_name])
      |> Ash.Query.filter(entity_chartering_agency_code == ^agency_code)
      |> Ash.Query.limit(1)
      |> Ash.read!(authorize?: false)
      |> List.first()

    %{
      code: agency_code,
      name: (sample && sample.entity_chartering_agency_name) || agency_code,
      school_count: length(schools)
    }
  rescue
    _ -> %{code: agency_code, name: agency_code, school_count: length(schools)}
  end

  defp load_mstep_stats([], _year), do: []

  defp load_mstep_stats(building_codes, year) do
    from(s in "mde_school_vs_lea_snapshots",
      where: s.building_code in ^building_codes and s.school_year == ^year,
      select: %{
        building_code: s.building_code,
        school_name: s.school_name,
        no_lea_found: s.no_lea_found,
        school_pct: fragment("(?->>'school_pct')::float", s.all_subjects_avg),
        lea_pct: fragment("(?->>'lea_pct')::float", s.all_subjects_avg),
        delta: fragment("(?->>'delta')::float", s.all_subjects_avg)
      }
    )
    |> Repo.all()
    |> Enum.sort_by(fn s -> if s.no_lea_found, do: -9999.0, else: s.delta || -9999.0 end, :desc)
  rescue
    _ -> []
  end

  defp load_sat_stats([], _year), do: []

  defp load_sat_stats(building_codes, year) do
    # Step 1: get LEA district codes from snapshots
    snapshot_map =
      from(s in "mde_school_vs_lea_snapshots",
        where: s.building_code in ^building_codes and s.school_year == ^year,
        select: {s.building_code, s.lea_district_code, s.no_lea_found}
      )
      |> Repo.all()
      |> Map.new(fn {bc, ldc, nlf} -> {bc, %{lea_district_code: ldc, no_lea_found: nlf}} end)

    # Step 2: fallback to entity_geographic_lea_district_code for missing/no_lea buildings
    fallback_codes =
      Enum.filter(building_codes, fn bc ->
        case Map.get(snapshot_map, bc) do
          nil -> true
          %{no_lea_found: true} -> true
          _ -> false
        end
      end)

    entity_lea_map =
      if fallback_codes == [] do
        %{}
      else
        from(e in "mde_entity_masters",
          where:
            e.entity_code in ^fallback_codes and
              not is_nil(e.entity_geographic_lea_district_code) and
              e.entity_geographic_lea_district_code != "",
          select: {e.entity_code, e.entity_geographic_lea_district_code}
        )
        |> Repo.all()
        |> Map.new()
      end

    # Merge snapshot + entity fallback
    lea_map =
      Map.new(building_codes, fn bc ->
        case Map.get(snapshot_map, bc) do
          %{no_lea_found: false} = entry ->
            {bc, entry}

          _ ->
            case Map.get(entity_lea_map, bc) do
              nil -> {bc, %{lea_district_code: nil, no_lea_found: true}}
              ldc -> {bc, %{lea_district_code: ldc, no_lea_found: false}}
            end
        end
      end)

    # Step 3: school SAT results
    school_sat =
      from(r in "mde_sat_results",
        where:
          r.building_code in ^building_codes and r.school_year == ^year and
            r.rollup_level == "building" and r.subgroup == "All Students",
        select: %{
          building_code: r.building_code,
          building_name: r.building_name,
          score: r.all_subject_score_average
        }
      )
      |> Repo.all()
      |> Map.new(&{&1.building_code, &1})

    # Step 4: LEA SAT results
    lea_codes =
      lea_map |> Map.values() |> Enum.map(& &1.lea_district_code) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    lea_sat =
      if lea_codes == [] do
        %{}
      else
        from(r in "mde_sat_results",
          where:
            r.district_code in ^lea_codes and r.school_year == ^year and
              r.rollup_level == "district" and r.subgroup == "All Students",
          select: %{district_code: r.district_code, score: r.all_subject_score_average}
        )
        |> Repo.all()
        |> Map.new(&{&1.district_code, &1.score})
      end

    # Step 5: build rows
    building_codes
    |> Enum.map(fn bc ->
      lea_info = Map.get(lea_map, bc, %{lea_district_code: nil, no_lea_found: true})
      school_info = Map.get(school_sat, bc)
      school_score = school_info && decimal_to_float(school_info.score)
      school_name = (school_info && school_info.building_name) || bc

      lea_score =
        if lea_info.no_lea_found or is_nil(lea_info.lea_district_code) do
          nil
        else
          raw = Map.get(lea_sat, lea_info.lea_district_code)
          raw && decimal_to_float(raw)
        end

      delta = if school_score && lea_score, do: school_score - lea_score, else: nil

      {no_lea, exclusion_reason} =
        cond do
          is_nil(school_score) ->
            {true, "No school SAT data"}

          lea_info.no_lea_found and is_nil(Map.get(entity_lea_map, bc)) ->
            {true, "No geographic LEA assigned"}

          is_nil(lea_score) ->
            {true, "LEA has no SAT data (#{lea_info.lea_district_code})"}

          true ->
            {false, nil}
        end

      %{
        building_code: bc,
        school_name: school_name,
        school_score: school_score,
        lea_score: lea_score,
        delta: delta,
        no_lea_found: no_lea,
        exclusion_reason: exclusion_reason
      }
    end)
    |> Enum.reject(fn s -> is_nil(s.school_score) and s.school_name == s.building_code end)
    |> Enum.sort_by(fn s -> if s.no_lea_found, do: -99_999.0, else: s.delta || -99_999.0 end, :desc)
  rescue
    _ -> []
  end

  # ---------------------------------------------------------------------------
  # Formatters
  # ---------------------------------------------------------------------------

  defp format_schools(schools) do
    Enum.map(schools, fn s ->
      %{
        name: s.entity_official_name || s.entity_code,
        district_code: s.district_code,
        county: s.entity_county_name,
        grades: s.entity_actual_grades || s.entity_authorized_grades
      }
    end)
  end

  defp format_section(stats, :mstep) do
    comparable = Enum.reject(stats, & &1.no_lea_found)
    excluded = Enum.filter(stats, & &1.no_lea_found)

    %{
      exceeds: Enum.count(comparable, fn s -> (s.delta || 0) > 0 end),
      below: Enum.count(comparable, fn s -> (s.delta || 0) <= 0 end),
      no_data: length(excluded),
      total_comparable: length(comparable),
      schools:
        Enum.map(stats, fn s ->
          %{
            school_name: s.school_name || s.building_code,
            building_code: s.building_code,
            school_pct: s.school_pct,
            lea_pct: s.lea_pct,
            delta: s.delta,
            no_lea_found: s.no_lea_found
          }
        end),
      excluded:
        Enum.map(excluded, fn s ->
          %{school_name: s.school_name || s.building_code, building_code: s.building_code}
        end)
    }
  end

  defp format_section(stats, :sat) do
    comparable = Enum.reject(stats, & &1.no_lea_found)
    excluded = Enum.filter(stats, & &1.no_lea_found)

    %{
      exceeds: Enum.count(comparable, fn s -> (s.delta || 0) > 0 end),
      below: Enum.count(comparable, fn s -> (s.delta || 0) <= 0 end),
      no_data: length(excluded),
      total_comparable: length(comparable),
      schools:
        Enum.map(stats, fn s ->
          %{
            school_name: s.school_name || s.building_code,
            building_code: s.building_code,
            school_score: s.school_score,
            lea_score: s.lea_score,
            delta: s.delta,
            no_lea_found: s.no_lea_found
          }
        end),
      excluded:
        Enum.map(excluded, fn s ->
          %{
            school_name: s.school_name || s.building_code,
            building_code: s.building_code,
            exclusion_reason: s.exclusion_reason || "No comparison available"
          }
        end)
    }
  end

  defp decimal_to_float(nil), do: nil
  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp decimal_to_float(f) when is_float(f), do: f
  defp decimal_to_float(i) when is_integer(i), do: i * 1.0
end
