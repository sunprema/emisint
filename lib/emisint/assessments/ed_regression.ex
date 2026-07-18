defmodule Emisint.Assessments.EdRegression do
  @moduledoc """
  ED% vs performance data for the ESP Portfolio "Regression" tab: one point
  per school (X = economically-disadvantaged enrollment %, Y = M-STEP or SAT
  performance), plus statewide threshold values for the quadrant crosshair
  and a least-squares regression line.

  The school population is `Emisint.Assessments.EmoPortfolio.resolve_schools/1`
  — the same override-aware list used by the ESP Portfolio dashboards and PDF
  export — so manual add/remove edits are reflected here automatically.
  """

  import Ecto.Query, only: [from: 2]

  alias Emisint.Assessments.EmoPortfolio
  alias Emisint.Repo

  @doc """
  M-STEP vs ED% analysis for `management_organization` in `school_year`.
  Returns `%{points:, excluded:, thresholds:, regression:}` — see
  `build_analysis/4`.
  """
  def mstep_analysis(management_organization, school_year) do
    build_analysis(management_organization, school_year, &mstep_value_map/2, &state_mstep_pct/1)
  end

  @doc """
  SAT vs ED% analysis for `management_organization` in `school_year`. Same
  shape as `mstep_analysis/2`.
  """
  def sat_analysis(management_organization, school_year) do
    build_analysis(management_organization, school_year, &sat_value_map/2, &state_sat_score/1)
  end

  # ---------------------------------------------------------------------------
  # Analysis assembly
  # ---------------------------------------------------------------------------

  # `points`: %{school_name, building_code, ed_pct, value, quadrant} for every
  #   resolved school with both an ED% and a performance value.
  # `excluded`: resolved schools missing one or both values (school_name,
  #   building_code, ed_pct, value — the nil ones show why they're excluded).
  # `thresholds`: %{ed_pct:, value:} statewide averages (the quadrant crosshair).
  # `regression`: %{slope:, intercept:} | nil (nil when fewer than 3 points).
  defp build_analysis(
         management_organization,
         school_year,
         value_map_fetcher,
         state_value_fetcher
       ) do
    {schools, _contact_map} = EmoPortfolio.resolve_schools(management_organization)
    building_codes = schools |> Enum.map(& &1.entity_code) |> Enum.reject(&is_nil/1)

    ed_map = ed_pct_map(building_codes, school_year)
    value_map = value_map_fetcher.(building_codes, school_year)

    rows =
      Enum.map(schools, fn s ->
        %{
          school_name: s.entity_official_name,
          building_code: s.entity_code,
          ed_pct: Map.get(ed_map, s.entity_code),
          value: Map.get(value_map, s.entity_code)
        }
      end)

    {points, excluded} = Enum.split_with(rows, &(&1.ed_pct && &1.value))

    thresholds = %{ed_pct: state_ed_pct(school_year), value: state_value_fetcher.(school_year)}
    regression = linear_regression(points)
    points = Enum.map(points, &Map.put(&1, :quadrant, classify(&1, thresholds)))

    %{points: points, excluded: excluded, thresholds: thresholds, regression: regression}
  rescue
    _ -> %{points: [], excluded: [], thresholds: %{ed_pct: nil, value: nil}, regression: nil}
  end

  # ---------------------------------------------------------------------------
  # Per-school value maps (building_code => value)
  # ---------------------------------------------------------------------------

  defp ed_pct_map([], _school_year), do: %{}

  defp ed_pct_map(building_codes, school_year) do
    from(e in "mde_enrollment_results",
      where:
        e.building_code in ^building_codes and e.rollup_level == "building" and
          e.school_year == ^school_year,
      select: %{
        building_code: e.building_code,
        total: e.total_enrollment,
        ed: e.economic_disadvantaged_enrollment
      }
    )
    |> Repo.all()
    |> Map.new(fn r -> {r.building_code, safe_pct(r.ed, r.total)} end)
  end

  defp mstep_value_map([], _school_year), do: %{}

  defp mstep_value_map(building_codes, school_year) do
    from(s in "mde_school_vs_lea_snapshots",
      where: s.building_code in ^building_codes and s.school_year == ^school_year,
      select: %{
        building_code: s.building_code,
        school_pct: fragment("(?->>'school_pct')::float", s.all_subjects_avg)
      }
    )
    |> Repo.all()
    |> Map.new(fn r -> {r.building_code, r.school_pct} end)
  end

  defp sat_value_map([], _school_year), do: %{}

  defp sat_value_map(building_codes, school_year) do
    from(r in "mde_sat_results",
      where:
        r.building_code in ^building_codes and r.school_year == ^school_year and
          r.rollup_level == "building" and r.subgroup == "All Students",
      select: %{building_code: r.building_code, score: r.all_subject_score_average}
    )
    |> Repo.all()
    |> Map.new(fn r -> {r.building_code, decimal_to_float(r.score)} end)
  end

  # ---------------------------------------------------------------------------
  # Statewide thresholds (the quadrant crosshair)
  # ---------------------------------------------------------------------------

  defp state_ed_pct(school_year) do
    from(e in "mde_enrollment_results",
      where: e.rollup_level == "isd" and e.isd_code == "0" and e.school_year == ^school_year,
      select: %{total: e.total_enrollment, ed: e.economic_disadvantaged_enrollment}
    )
    |> Repo.one()
    |> case do
      nil -> nil
      %{total: total, ed: ed} -> safe_pct(ed, total)
    end
  end

  defp state_mstep_pct(school_year) do
    from(s in "mde_school_vs_lea_snapshots",
      where: s.school_year == ^school_year,
      select: fragment("(?->>'state_pct')::float", s.all_subjects_avg),
      limit: 1
    )
    |> Repo.one()
  end

  defp state_sat_score(school_year) do
    from(r in "mde_sat_results",
      where:
        r.rollup_level == "isd" and r.isd_code == "0" and r.school_year == ^school_year and
          r.subgroup == "All Students",
      select: r.all_subject_score_average
    )
    |> Repo.one()
    |> decimal_to_float()
  end

  # ---------------------------------------------------------------------------
  # Regression + quadrant classification
  # ---------------------------------------------------------------------------

  @doc false
  def linear_regression(points) when length(points) < 3, do: nil

  def linear_regression(points) do
    n = length(points)
    xs = Enum.map(points, & &1.ed_pct)
    ys = Enum.map(points, & &1.value)
    mean_x = Enum.sum(xs) / n
    mean_y = Enum.sum(ys) / n

    {num, den} =
      Enum.zip(xs, ys)
      |> Enum.reduce({0.0, 0.0}, fn {x, y}, {num, den} ->
        dx = x - mean_x
        {num + dx * (y - mean_y), den + dx * dx}
      end)

    if den == 0 do
      nil
    else
      slope = num / den
      %{slope: slope, intercept: mean_y - slope * mean_x}
    end
  end

  # "Beating the odds" scheme: high ED + high performance (outperforming
  # expectations) = green; low ED + low performance (underperforming despite
  # advantage) = red; the other two ("as expected" either way) = yellow.
  defp classify(%{ed_pct: ed, value: v}, %{ed_pct: ed_t, value: v_t})
       when is_number(ed_t) and is_number(v_t) do
    cond do
      ed >= ed_t and v >= v_t -> :green
      ed < ed_t and v < v_t -> :red
      true -> :yellow
    end
  end

  defp classify(_point, _thresholds), do: :yellow

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp safe_pct(nil, _), do: nil
  defp safe_pct(_, nil), do: nil
  defp safe_pct(_, 0), do: nil
  defp safe_pct(numerator, denominator), do: Float.round(numerator / denominator * 100, 1)

  defp decimal_to_float(nil), do: nil
  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp decimal_to_float(f) when is_float(f), do: f
  defp decimal_to_float(i) when is_integer(i), do: i * 1.0
end
