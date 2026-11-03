defmodule Emisint.NdInsights.SurveyBenchmark do
  @moduledoc """
  Statewide **middle-school** (grades 6–8) Engagement Survey benchmarks from
  the ND Student Engagement Survey technical briefs (Cognia), and the check
  that decides whether one may be compared with a school's ND Insights survey
  results.

  **Why not the Insights state row.** The "State of North Dakota" Engagement
  rows aggregate all three survey versions, grades 3–12: for 2021-22 and
  2024-25 they equal the brief's elementary + middle + high counts divided by
  all respondents (e.g. 2024-25 Behavioral Committed 40,857 / 80,214 = 51%;
  Insights 0.51). A middle school is a different population.

  **The benchmark.** Figure 5 of each brief gives the number of middle-school
  respondents classified Committed, Compliant and Disengaged in each domain
  (each domain sums to the brief's middle-school respondent total, Table 2).
  The classification is the one Insights uses: a student's modal engagement
  type in the domain, as a share of respondents who completed the survey
  (brief §6). The brief has no Overall classification by grade span, so the
  Insights "Overall" area has no benchmark.

  **When it applies to a school.** Only for the same year, and only when the
  brief's Appendix C lists the school's respondents under the middle-school
  version alone **and** the brief's per-domain "% Committed" for the school
  falls inside the school's published Insights Committed range for every
  domain imported (at least one), which confirms that the Insights figure is that same population.
  Fort Yates passes for 2021-22 and 2024-25; in 2022-23 and 2023-24 its
  Insights figure also includes elementary-version respondents (13 and 7), so
  no middle-school benchmark applies.

  Values are the brief's published counts; nothing is interpolated, rounded
  into ranges or carried across years. Only the Fort Yates Appendix C rows are
  recorded (pilot scope).
  """

  @domains [:engagement_behavioral, :engagement_cognitive, :engagement_emotional]
  @levels ~w(Committed Compliant Disengaged)

  # Figure 5 counts: {Committed, Compliant, Disengaged} per domain.
  @briefs %{
    "2021-2022" => %{
      short: "ND SES technical brief 2021-22, Figure 5",
      title:
        "Technical Brief: North Dakota Student Engagement Survey, 2021-22 (Cognia, V1.0, June 30, 2022)",
      file: "ND-2122-SES-Technical-Brief.pdf",
      url:
        "https://nddpi.onlinehelp.cognia.org/wp-content/uploads/sites/20/2022/07/ND-2122-SES-Technical-Brief.pdf",
      sha256: "99d8c3b83054ec4bf9eada48669290b0d6437a312bc675393ba4cc13d7af97b2",
      respondents: 23_638,
      counts: %{
        engagement_behavioral: {10_960, 10_144, 2_534},
        engagement_cognitive: {8_104, 12_501, 3_033},
        engagement_emotional: {7_355, 10_576, 5_707}
      },
      schools: %{"4300429212" => [{"Middle", 52, {19, 27, 25}}]}
    },
    "2022-2023" => %{
      short: "ND SES technical brief 2022-23, Figure 5",
      title:
        "Technical Brief: North Dakota Student Engagement Survey, 2022-23 (Cognia, V1.0, June 30, 2023)",
      file: "ND-2223-SES-Technical-Brief.pdf",
      url:
        "https://nddpi.onlinehelp.cognia.org/wp-content/uploads/sites/20/2023/06/ND-2223-SES-Technical-Brief.pdf",
      sha256: "733e8f9f4f970af14e3c35e51c2e711de99338dff71b4881358b51d9d00178c7",
      respondents: nil,
      counts: nil,
      schools: %{"4300429212" => [{"Elementary", 13, {38, 54, 54}}, {"Middle", 42, {38, 38, 19}}]}
    },
    "2023-2024" => %{
      short: "ND SES technical brief 2023-24, Figure 5",
      title:
        "Technical Brief: North Dakota Student Engagement Survey, 2023-24 (Cognia, V1.0, April 1, 2024)",
      file: "ND-2324-SES-Technical-Brief.pdf",
      url:
        "https://nddpi.onlinehelp.cognia.org/wp-content/uploads/sites/20/2024/04/ND-2324-SES-Technical-Brief.pdf",
      sha256: "3a4abc4c083b7293825b51c42c1eb9be2da4b55f8e7b76c23496303e9123987b",
      respondents: nil,
      counts: nil,
      schools: %{"4300429212" => [{"Elementary", 7, {71, 57, 57}}, {"Middle", 46, {41, 35, 30}}]}
    },
    "2024-2025" => %{
      short: "ND SES technical brief 2024-25, Figure 5",
      title:
        "Technical Brief: North Dakota Student Engagement Survey, 2024-25 (Cognia, V1.0, April 3, 2025)",
      file: "ND-2425-SES-Technical-Brief.pdf",
      url:
        "https://nddpi.onlinehelp.cognia.org/wp-content/uploads/sites/20/2025/04/ND-2425-SES-Technical-Brief.pdf",
      sha256: "f8c1e3538a26ea166e5f7e0436a907f5fd0e987924ed2cd51eb4a9eb8a2bd3e9",
      respondents: 24_900,
      counts: %{
        engagement_behavioral: {12_136, 10_222, 2_542},
        engagement_cognitive: {8_817, 12_973, 3_110},
        engagement_emotional: {8_382, 10_545, 5_973}
      },
      schools: %{"4300429212" => [{"Middle", 98, {34, 31, 31}}]}
    }
  }

  @doc "The recorded brief for a year, or nil."
  def brief(year), do: @briefs[year]

  @doc "The domains a brief benchmarks (not Overall)."
  def domains, do: @domains

  @doc """
  Whether a middle-school benchmark applies to `institution_id` in `year`,
  given the school's Engagement rows for that year
  (`SchoolResults.engagement/2`, keyed by area):

    * `{:ok, brief}`
    * `{:no_brief, year}` — no brief with middle-school counts is recorded for the year
    * `{:not_listed, brief}` — the school isn't in the brief's Appendix C rows recorded here
    * `{:mixed_versions, brief, versions}` — respondents took more than one survey version
    * `{:does_not_reconcile, brief, domain}` — the brief's % Committed is outside the Insights range
  """
  def compatibility(institution_id, year, school_areas) do
    case @briefs[year] do
      nil -> {:no_brief, year}
      brief -> listed(brief, brief.schools[institution_id], year, school_areas)
    end
  end

  defp listed(brief, nil, _year, _areas), do: {:not_listed, brief}

  defp listed(%{counts: nil}, [{"Middle", _, _}], year, _areas), do: {:no_brief, year}

  defp listed(brief, [{"Middle", _n, committed}], _year, areas) do
    case reconciles(areas, committed) do
      :ok -> {:ok, brief}
      {:does_not_reconcile, domain} -> {:does_not_reconcile, brief, domain}
    end
  end

  defp listed(brief, versions, _year, _areas), do: {:mixed_versions, brief, versions}

  # Every domain the school has a published Committed value for must contain
  # the brief's figure; at least one must be checked.
  defp reconciles(school_areas, committed) do
    checks =
      for {domain, pct} <- Enum.zip(@domains, Tuple.to_list(committed)),
          row = get_in(school_areas, [domain, "Committed"]),
          row != nil,
          do: {domain, within?(row, Decimal.div(Decimal.new(pct), 100))}

    case Enum.find(checks, fn {_, ok?} -> not ok? end) do
      _ when checks == [] -> {:does_not_reconcile, hd(@domains)}
      nil -> :ok
      {domain, false} -> {:does_not_reconcile, domain}
    end
  end

  defp within?(%{value_state: :range, range_low: low, range_high: high}, v),
    do: Decimal.compare(v, low) != :lt and Decimal.compare(v, high) != :gt

  defp within?(%{value_state: :exact, value: value}, v), do: Decimal.equal?(value, v)
  defp within?(_row, _v), do: false

  @doc """
  The benchmark for one domain and level as a published-value row
  (`%{value_state: :exact, unit: :proportion, value, count, respondents}`),
  or nil for a domain the brief doesn't report (Overall).
  """
  def value(%{counts: counts, respondents: n}, domain, level) when is_map(counts) do
    with {_, _, _} = triple <- counts[domain],
         index when is_integer(index) <- Enum.find_index(@levels, &(&1 == level)) do
      count = elem(triple, index)

      %{
        value_state: :exact,
        unit: :proportion,
        value: Decimal.div(Decimal.new(count), Decimal.new(n)),
        count: count,
        respondents: n
      }
    else
      _ -> nil
    end
  end

  @doc "A short source line, e.g. for the PDF sources list."
  def source(%{title: title, url: url, sha256: sha}),
    do:
      "#{title}, Figure 5 (middle school counts) and Appendix C: #{url} (sha256 #{String.slice(sha, 0, 12)}…)"
end
