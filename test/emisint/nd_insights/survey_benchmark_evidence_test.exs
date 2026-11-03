defmodule Emisint.NdInsights.SurveyBenchmarkEvidenceTest do
  @moduledoc """
  Reproduces the evidence behind `Emisint.NdInsights.SurveyBenchmark` from
  numbers transcribed from the ND Student Engagement Survey technical briefs
  (see docs/nd_insights_benchmarks.md for the sources, pages and figures) and
  the tracked Insights Engagement fixture.
  """
  use ExUnit.Case, async: true

  alias Emisint.NdInsights.SurveyBenchmark

  @fixture Path.expand(
             "../../fixtures/nd_insights/with_state/Insights-Engagement-Emotional-All-CSV-v20251202.csv",
             __DIR__
           )

  # Brief Table 2 (respondents by version) and Figures 4–6 (respondents
  # classified Committed, Compliant, Disengaged per domain).
  @briefs %{
    "2021-2022" => %{
      n: %{elementary: 24_126, middle: 23_638, high: 27_670},
      elementary: %{
        engagement_behavioral: {16_022, 6_633, 1_471},
        engagement_cognitive: {14_620, 8_344, 1_162},
        engagement_emotional: {15_566, 4_065, 4_495}
      },
      middle: %{
        engagement_behavioral: {10_960, 10_144, 2_534},
        engagement_cognitive: {8_104, 12_501, 3_033},
        engagement_emotional: {7_355, 10_576, 5_707}
      },
      high: %{
        engagement_behavioral: {10_559, 13_225, 3_886},
        engagement_cognitive: {5_871, 18_491, 3_308},
        engagement_emotional: {7_834, 12_918, 6_918}
      }
    },
    "2024-2025" => %{
      n: %{elementary: 25_107, middle: 24_900, high: 30_207},
      elementary: %{
        engagement_behavioral: {16_556, 7_125, 1_426},
        engagement_cognitive: {15_076, 8_774, 1_257},
        engagement_emotional: {16_132, 4_390, 4_585}
      },
      middle: %{
        engagement_behavioral: {12_136, 10_222, 2_542},
        engagement_cognitive: {8_817, 12_973, 3_110},
        engagement_emotional: {8_382, 10_545, 5_973}
      },
      high: %{
        engagement_behavioral: {12_165, 14_650, 3_392},
        engagement_cognitive: {7_373, 19_963, 2_871},
        engagement_emotional: {9_759, 13_813, 6_635}
      }
    }
  }

  # Insights "State of North Dakota" Committed / Disengaged values from the
  # Behavioral and Cognitive downloads (v20251202; not in the test fixtures).
  # Emotional is read from the tracked fixture.
  @insights_state %{
    {"2021-2022", :engagement_behavioral} => {"0.50", "0.10"},
    {"2021-2022", :engagement_cognitive} => {"0.38", "0.10"},
    {"2024-2025", :engagement_behavioral} => {"0.51", "0.09"},
    {"2024-2025", :engagement_cognitive} => {"0.39", "0.09"}
  }

  # The tracked fixture's rows: %{{institution_id, level} => %{year => cell}}.
  defp fixture do
    [header | rows] = @fixture |> File.read!() |> String.split(~r/\r?\n/, trim: true)
    years = header |> String.split(",") |> Enum.drop(5)

    Map.new(rows, fn line ->
      [_, _, id, _, level | cells] = String.split(line, ",")
      {{id, level}, Map.new(Enum.zip(years, cells))}
    end)
  end

  defp share(count, n), do: Decimal.div(Decimal.new(count), Decimal.new(n))
  defp two_dp(d), do: d |> Decimal.round(2) |> Decimal.to_string(:normal)

  test "each grade span's counts sum to its Table 2 total, and the recorded middle-school counts are the brief's" do
    for {year, brief} <- @briefs,
        span <- [:elementary, :middle, :high],
        {_domain, counts} <- brief[span] do
      assert counts |> Tuple.to_list() |> Enum.sum() == brief.n[span], "#{year} #{span}"
    end

    for {year, brief} <- @briefs do
      recorded = SurveyBenchmark.brief(year)
      assert recorded.respondents == brief.n.middle
      assert recorded.counts == brief.middle
    end
  end

  test "all three spans together reproduce the Insights statewide (grades 3–12) values" do
    rows = fixture()

    for {year, brief} <- @briefs, domain <- SurveyBenchmark.domains() do
      total = brief.n |> Map.values() |> Enum.sum()

      all = fn index ->
        Enum.sum(for span <- [:elementary, :middle, :high], do: elem(brief[span][domain], index))
      end

      {committed, disengaged} =
        case domain do
          :engagement_emotional ->
            {rows[{"99999", "Committed"}][year], rows[{"99999", "Disengaged"}][year]}

          _ ->
            @insights_state[{year, domain}]
        end

      assert two_dp(share(all.(0), total)) == two_dp(Decimal.new(committed)), "#{year} #{domain}"
      assert two_dp(share(all.(2), total)) == two_dp(Decimal.new(disengaged)), "#{year} #{domain}"
    end
  end

  test "Fort Yates: middle-only years reconcile with Insights; mixed-version years are not compared" do
    rows = fixture()
    emotional = &rows[{"4300429212", "Committed"}][&1]

    # Appendix C, Emotional % Committed (third figure), inside the published range.
    for year <- ["2021-2022", "2024-2025"] do
      [{"Middle", _n, {_, _, pct}}] = SurveyBenchmark.brief(year).schools["4300429212"]
      [low, high] = year |> emotional.() |> String.split("-") |> Enum.map(&Decimal.new/1)
      v = share(pct, 100)
      assert Decimal.compare(v, low) != :lt and Decimal.compare(v, high) != :gt
    end

    # 2022-23 and 2023-24 list elementary- and middle-version respondents.
    for year <- ["2022-2023", "2023-2024"] do
      assert [{"Elementary", _, _}, {"Middle", _, _}] =
               SurveyBenchmark.brief(year).schools["4300429212"]

      assert {:mixed_versions, _, _} =
               SurveyBenchmark.compatibility("4300429212", year, %{})
    end
  end
end
