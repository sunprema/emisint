defmodule Emisint.NdInsights.StateComparisonTest do
  use ExUnit.Case, async: true

  alias Emisint.NdInsights.StateComparison

  @year "2024-2025"
  @filters %{year: @year, type: "Comp", subgroup: "All"}

  # A published proportion: a number is exact, a `{low, high}` tuple a range,
  # `:suppressed` suppressed.
  defp row(dataset, measure, value, attrs \\ []) do
    base = %{
      dataset: dataset,
      academic_year: @year,
      subject: "Math",
      grade: "6",
      assessment_type: if(dataset == :growth_rate, do: nil, else: "Comp"),
      subgroup: "All",
      accommodations: "All",
      measure: measure,
      engagement_level: nil,
      unit: :proportion,
      value_state: :exact,
      value: nil,
      range_low: nil,
      range_high: nil
    }

    base
    |> Map.merge(published(value))
    |> Map.merge(Map.new(attrs))
  end

  defp published(:suppressed), do: %{value_state: :suppressed}

  defp published({low, high}),
    do: %{value_state: :range, range_low: Decimal.new(low), range_high: Decimal.new(high)}

  defp published(value), do: %{value_state: :exact, value: Decimal.new(value)}

  defp perf(measure, value, attrs \\ []), do: row(:assessment_performance, measure, value, attrs)

  defp achievement(school, state, key \\ {"Math", "6"}),
    do: StateComparison.for_filters(school, state, @filters).achievement[key]

  # Engagement rows for one area: Committed, Compliant, Disengaged values (nil skips one).
  defp engagement_rows(area, committed, compliant, disengaged, attrs \\ []) do
    {level, attrs} = Keyword.pop(attrs, :level)
    {year, attrs} = Keyword.pop(attrs, :year, @year)

    pairs =
      if level,
        do: [{level, committed}],
        else: [{"Committed", committed}, {"Compliant", compliant}, {"Disengaged", disengaged}]

    for {lvl, value} <- pairs, value != nil do
      row(
        area,
        nil,
        value,
        [
          engagement_level: lvl,
          academic_year: year,
          subject: nil,
          grade: nil,
          assessment_type: nil,
          subgroup: nil
        ] ++
          attrs
      )
    end
  end

  describe "exact published values" do
    test "lower Novice and higher Advanced are favorable; the opposite is unfavorable" do
      c = achievement([perf("Novice", "0.15")], [perf("Novice", "0.25")])
      assert %{status: :favorable, reason: :lower} = c["Novice"]
      assert StateComparison.tone(c["Novice"]) == :success

      c = achievement([perf("Novice", "0.75")], [perf("Novice", "0.25")])
      assert %{status: :unfavorable, reason: :higher} = c["Novice"]
      assert StateComparison.tone(c["Novice"]) == :error

      c = achievement([perf("Advanced", "0.35")], [perf("Advanced", "0.21")])
      assert %{status: :favorable, reason: :higher} = c["Advanced"]

      c = achievement([perf("Advanced", "0.1")], [perf("Advanced", "0.21")])
      assert %{status: :unfavorable, reason: :lower} = c["Advanced"]
    end

    test "equal exact values match the state, with a neutral tone" do
      c = achievement([perf("Novice", "0.3")], [perf("Novice", "0.3")])["Novice"]
      assert %{status: :matches, reason: :equal} = c
      assert StateComparison.tone(c) == :neutral
      assert StateComparison.short_label(c) == "Matches state"
      assert StateComparison.explanation(c) =~ "both published as exact values and are equal"

      # Exact values are compared as published, with no allowance.
      c = achievement([perf("Novice", "0.31")], [perf("Novice", "0.3")])["Novice"]
      assert %{status: :unfavorable, reason: :higher} = c
    end

    test "Proficient or Advanced is compared as an exact sum; Proficient alone is not rated" do
      school = [perf("Proficient", "0.1"), perf("Advanced", "0.05")]
      state = [perf("Proficient", "0.27"), perf("Advanced", "0.21")]
      c = achievement(school, state)

      assert %{status: :unfavorable, school_text: "15%", state_text: "48%"} =
               c[:proficient_or_advanced]

      assert %{status: :neutral, reason: :intermediate} = c["Proficient"]
    end

    test "Approaching Proficiency is not rated even when far from the state" do
      c = achievement([perf("Partially", "0.9")], [perf("Partially", "0.28")])
      assert %{status: :neutral, reason: :intermediate, state_text: "28%"} = c["Partially"]
      assert StateComparison.tone(c["Partially"]) == :muted
      assert StateComparison.short_label(c["Partially"]) == "Intermediate level"
      assert StateComparison.compact_label(c["Partially"]) == "Intermediate"
      assert StateComparison.benchmark_line(c["Partially"]) == "ND 28%"
    end

    test "growth: Does not meet lower; Exceeds, Meets or Exceeds and the percentile higher" do
      g = &row(:growth_rate, &1, &2)
      p = &row(:growth_rate, &1, &2, unit: :percentile)

      school = [
        g.("DoesNotMeet", "0.35"),
        g.("Approaches", "0.2"),
        g.("Meets", "0.1"),
        g.("Exceeds", "0.05"),
        p.("OverallGrowthPercentile", "64"),
        row(:growth_rate, "OverallGrowthLevel", "2", unit: :level)
      ]

      state = [
        g.("DoesNotMeet", "0.06"),
        g.("Approaches", "0.43"),
        g.("Meets", "0.43"),
        g.("Exceeds", "0.08"),
        p.("OverallGrowthPercentile", "50"),
        row(:growth_rate, "OverallGrowthLevel", "3", unit: :level)
      ]

      c = StateComparison.for_filters(school, state, @filters).growth[{"Math", "6"}]

      assert %{status: :unfavorable, reason: :higher} = c["DoesNotMeet"]
      assert %{status: :unfavorable, reason: :lower} = c[:meets_or_exceeds]
      assert %{status: :unfavorable, reason: :lower} = c["Exceeds"]
      assert %{status: :neutral, reason: :intermediate} = c["Meets"]
      assert %{status: :neutral, reason: :intermediate} = c["Approaches"]

      assert %{status: :favorable, reason: :higher, school_text: "64"} =
               c["OverallGrowthPercentile"]

      assert %{status: :neutral, reason: :no_interpretation} = c["OverallGrowthLevel"]

      below = [p.("OverallGrowthPercentile", "35")]
      c = StateComparison.for_filters(below, state, @filters).growth[{"Math", "6"}]
      assert %{status: :unfavorable} = c["OverallGrowthPercentile"]

      same = [p.("OverallGrowthPercentile", "50")]
      c = StateComparison.for_filters(same, state, @filters).growth[{"Math", "6"}]
      assert %{status: :matches} = c["OverallGrowthPercentile"]
    end
  end

  describe "published ranges: compared through their published bounds" do
    test "a range entirely above or below the state value gets a verdict, respecting direction" do
      # Novice (lower is better) 70%–79% vs 25%: entirely higher, unfavorable.
      c = achievement([perf("Novice", {"0.7", "0.79"})], [perf("Novice", "0.25")])["Novice"]
      assert %{status: :unfavorable, reason: :higher, school_text: "70%–79%"} = c
      assert StateComparison.explanation(c) =~ "whole published school range is above it"
      assert StateComparison.explanation(c) =~ "never midpoints"

      # The same range is favorable for a higher-is-better measure.
      c = achievement([perf("Advanced", {"0.7", "0.79"})], [perf("Advanced", "0.25")])
      assert %{status: :favorable, reason: :higher} = c["Advanced"]

      # Reversed: Novice 0%–10% vs 25% is favorable; Advanced 0%–10% vs 21% unfavorable.
      c = achievement([perf("Novice", {"0", "0.1"})], [perf("Novice", "0.25")])["Novice"]
      assert %{status: :favorable, reason: :lower} = c
      c = achievement([perf("Advanced", {"0", "0.1"})], [perf("Advanced", "0.21")])
      assert %{status: :unfavorable, reason: :lower} = c["Advanced"]
    end

    test "strictly apart by any amount is a verdict; no allowance is added" do
      # 0%–20% vs 21%: the published upper bound is below the state value.
      c = achievement([perf("Novice", {"0", "0.2"})], [perf("Novice", "0.21")])["Novice"]
      assert %{status: :favorable, reason: :lower} = c

      c = achievement([perf("Novice", {"0.3", "0.39"})], [perf("Novice", "0.29")])["Novice"]
      assert %{status: :unfavorable, reason: :higher} = c
    end

    test "a range containing the state value overlaps; sharing an endpoint touches; both yellow" do
      c = achievement([perf("Novice", {"0.2", "0.29"})], [perf("Novice", "0.25")])["Novice"]
      assert %{status: :inconclusive, reason: :overlap, detail: %{touch?: false}} = c
      assert StateComparison.tone(c) == :warning
      assert StateComparison.short_label(c) == "Overlaps ND"
      assert StateComparison.explanation(c) =~ "overlap, so the published values don't show"

      # Boundary equality: 0%–20% vs exactly 20%, and 20%–29% vs 20%.
      for range <- [{"0", "0.2"}, {"0.2", "0.29"}] do
        c = achievement([perf("Novice", range)], [perf("Novice", "0.2")])["Novice"]
        assert %{status: :inconclusive, detail: %{touch?: true}} = c
        assert StateComparison.short_label(c) == "Touches ND"
        assert StateComparison.explanation(c) =~ "share an endpoint"
      end
    end

    test "a state range is compared as an interval too" do
      c = achievement([perf("Novice", {"0.7", "0.79"})], [perf("Novice", {"0.2", "0.24"})])
      assert %{status: :unfavorable, school_text: "70%–79%", state_text: "20%–24%"} = c["Novice"]

      c = achievement([perf("Novice", {"0.2", "0.29"})], [perf("Novice", {"0.25", "0.29"})])
      assert %{status: :inconclusive, detail: %{touch?: false}} = c["Novice"]

      c = achievement([perf("Novice", {"0.2", "0.29"})], [perf("Novice", {"0.29", "0.35"})])
      assert %{status: :inconclusive, detail: %{touch?: true}} = c["Novice"]

      c = achievement([perf("Novice", {"0.2", "0.29"})], [perf("Novice", {"0.3", "0.35"})])
      assert %{status: :favorable} = c["Novice"]
    end

    test "a derived sum adds the published bounds" do
      # Proficient 0%–20% + Advanced 1% = 1%–21% vs 48% (27% + 21%): unfavorable.
      school = [perf("Proficient", {"0", "0.2"}), perf("Advanced", "0.01")]
      state = [perf("Proficient", "0.27"), perf("Advanced", "0.21")]

      assert %{status: :unfavorable, school_text: "1%–21%"} =
               achievement(school, state)[:proficient_or_advanced]

      # 20%–39% vs 42%: apart, unfavorable. 20%–39% vs 39%: touches.
      school = [perf("Proficient", {"0.2", "0.29"}), perf("Advanced", {"0", "0.1"})]

      assert %{status: :unfavorable} =
               achievement(school, [perf("Proficient", "0.36"), perf("Advanced", "0.06")])[
                 :proficient_or_advanced
               ]

      assert %{status: :inconclusive, detail: %{touch?: true}} =
               achievement(school, [perf("Proficient", "0.33"), perf("Advanced", "0.06")])[
                 :proficient_or_advanced
               ]
    end
  end

  describe "missing data and matching" do
    test "missing or suppressed values on either side are gray with the reason" do
      c = achievement([perf("Novice", "0.5")], [])["Novice"]
      assert %{status: :neutral, reason: :benchmark_unavailable} = c
      assert StateComparison.short_label(c) == "No ND value"

      c = achievement([perf("Novice", "0.5")], [perf("Novice", :suppressed)])["Novice"]
      assert %{status: :neutral, reason: :benchmark_suppressed} = c
      assert StateComparison.tone(c) == :muted

      c = achievement([perf("Novice", :suppressed)], [perf("Novice", "0.25")])
      assert %{reason: :school_unavailable, state_text: nil} = c["Novice"]

      # A suppressed component makes the derived sum unavailable on that side.
      school = [perf("Proficient", :suppressed), perf("Advanced", "0.1")]
      state = [perf("Proficient", "0.27"), perf("Advanced", "0.21")]
      assert %{reason: :school_unavailable} = achievement(school, state)[:proficient_or_advanced]
    end

    test "another year, assessment type, student group or grade is never substituted" do
      school = [perf("Novice", "0.75")]

      for state <- [
            [perf("Novice", "0.25", academic_year: "2023-2024")],
            [perf("Novice", "0.25", assessment_type: "Reg")],
            [perf("Novice", "0.25", subgroup: "Female")],
            [perf("Novice", "0.25", grade: "7")]
          ] do
        assert %{status: :neutral, reason: :benchmark_unavailable} =
                 achievement(school, state)["Novice"]
      end
    end

    test "All Grades with different grade coverage is context only, even when far apart" do
      school =
        for grade <- ["6", "7", "8", "All Grades"],
            do: perf("Novice", {"0.7", "0.79"}, grade: grade)

      wider_state =
        for grade <- ["3", "4", "5", "6", "7", "8", "All Grades"],
            do: perf("Novice", "0.28", grade: grade)

      c = achievement(school, wider_state, {"Math", "All Grades"})["Novice"]

      assert %{status: :neutral, reason: :grade_coverage} = c
      assert c.detail == %{school_grades: ~w(6 7 8), state_grades: ~w(3 4 5 6 7 8)}
      assert StateComparison.short_label(c) == "Context only"

      assert StateComparison.explanation(c) =~
               "this school 6, 7, 8; North Dakota 3, 4, 5, 6, 7, 8"

      # The matching grade rows are still compared.
      assert %{status: :unfavorable} = achievement(school, wider_state, {"Math", "6"})["Novice"]

      same_state =
        for grade <- ["6", "7", "8", "All Grades"], do: perf("Novice", "0.28", grade: grade)

      assert %{status: :unfavorable} =
               achievement(school, same_state, {"Math", "All Grades"})["Novice"]
    end

    test "Engagement without a verified middle-school benchmark is context only, never the grades 3–12 row" do
      school =
        engagement_rows(:engagement_emotional, {"0.1", "0.14"}, {"0.4", "0.44"}, {"0.4", "0.49"})

      state = engagement_rows(:engagement_emotional, "0.44", "0.43", "0.13")

      # No institution recorded in the brief: not listed.
      compared = StateComparison.for_filters(school, state, @filters)
      c = compared.engagement[:engagement_emotional]
      assert %{status: :neutral, reason: {:survey, {:not_listed, _}}} = c["Committed"]
      assert StateComparison.short_label(c["Committed"]) == "Context only"

      assert StateComparison.explanation(c["Committed"]) =~
               "Insights statewide (grades 3–12): 44%"

      assert %{status: :not_compared} = StateComparison.survey_note(compared.survey_benchmark)
    end
  end

  describe "Engagement: same-year middle-school benchmark (technical brief)" do
    @fy "4300429212"

    # Fort Yates 2024-25 as published on Insights: every domain 30%–34% Committed;
    # the brief lists 98 middle-school respondents at 34% / 31% / 31%.
    defp fy_survey(year, committed \\ {"0.3", "0.34"}) do
      for area <- [:engagement_behavioral, :engagement_cognitive, :engagement_emotional],
          {level, value} <- [
            {"Committed", committed},
            {"Compliant", {"0.5", "0.54"}},
            {"Disengaged", {"0.15", "0.19"}}
          ] do
        hd(engagement_rows(area, value, nil, nil, level: level, institution_id: @fy, year: year))
      end
    end

    test "a reconciled middle-only population is compared with the middle-school counts" do
      compared = StateComparison.for_filters(fy_survey("2024-2025"), [], @filters)
      assert {:ok, %{respondents: 24_900}} = compared.survey_benchmark

      assert %{status: :compared, text: text} =
               StateComparison.survey_note(compared.survey_benchmark)

      assert text =~ "2024-25"

      b = compared.engagement[:engagement_behavioral]

      # Committed 30%–34% vs 48.7% (12,136 of 24,900): higher is better, so red.
      assert %{status: :unfavorable, basis: :band} = b["Committed"]
      assert b["Committed"].state_text == "48.7% (ND grades 6–8: 12,136 of 24,900)"
      assert StateComparison.short_label(b["Committed"]) == "Unfavorable vs ND gr. 6–8"
      assert StateComparison.explanation(b["Committed"]) =~ "Figure 5"

      # Disengaged 15%–19% vs 10.2% (2,542 of 24,900): lower is better, so red.
      assert %{status: :unfavorable, reason: :higher} = b["Disengaged"]

      # Cognitive Disengaged 15%–19% vs 12.5% (3,110): apart, red; Compliant not rated.
      assert %{status: :unfavorable} = compared.engagement[:engagement_cognitive]["Disengaged"]
      assert %{status: :neutral, reason: :intermediate} = b["Compliant"]
    end

    test "Overall has no grade-span benchmark" do
      rows =
        fy_survey("2024-2025") ++
          engagement_rows(:engagement_overall, {"0.3", "0.34"}, nil, nil, institution_id: @fy)

      c =
        StateComparison.for_filters(rows, [], @filters).engagement[:engagement_overall][
          "Committed"
        ]

      assert %{status: :neutral, reason: :no_band_benchmark} = c
    end

    test "not compared when the brief's figures fall outside the published Insights range" do
      compared =
        StateComparison.for_filters(fy_survey("2024-2025", {"0.4", "0.44"}), [], @filters)

      assert {:does_not_reconcile, _, :engagement_behavioral} = compared.survey_benchmark
      assert %{status: :neutral} = compared.engagement[:engagement_behavioral]["Committed"]
    end

    test "not compared when respondents took more than one survey version, or with no brief" do
      compared =
        StateComparison.for_filters(fy_survey("2023-2024"), [], %{@filters | year: "2023-2024"})

      assert {:mixed_versions, _, [{"Elementary", 7, _}, {"Middle", 46, _}]} =
               compared.survey_benchmark

      assert StateComparison.survey_note(compared.survey_benchmark).text =~
               "Elementary 7 and Middle 46"

      assert %{status: :neutral} = compared.engagement[:engagement_behavioral]["Committed"]

      compared =
        StateComparison.for_filters(fy_survey("2019-2020"), [], %{@filters | year: "2019-2020"})

      assert {:no_brief, "2019-2020"} = compared.survey_benchmark
    end

    test "years are never mixed: 2021-22 uses its own brief's counts" do
      rows = fy_survey("2021-2022", {"0.15", "0.19"})

      # 2021-22 brief: Fort Yates 19% / 27% / 25% Committed; Cognitive and Emotional ranges differ.
      rows =
        Enum.map(rows, fn
          %{dataset: :engagement_cognitive, engagement_level: "Committed"} = r ->
            %{r | range_low: Decimal.new("0.25"), range_high: Decimal.new("0.29")}

          %{dataset: :engagement_emotional, engagement_level: "Committed"} = r ->
            %{r | range_low: Decimal.new("0.25"), range_high: Decimal.new("0.29")}

          r ->
            r
        end)

      compared = StateComparison.for_filters(rows, [], %{@filters | year: "2021-2022"})
      assert {:ok, %{respondents: 23_638}} = compared.survey_benchmark

      assert compared.engagement[:engagement_behavioral]["Committed"].state_text ==
               "46.4% (ND grades 6–8: 10,960 of 23,638)"
    end
  end

  describe "% tested and the 95% participation target" do
    defp tested(value, attrs \\ []),
      do: row(:assessment_participation, "PercentTested", value, [grade: "All Grades"] ++ attrs)

    defp tested_cmp(school_rows, filters \\ @filters, key \\ {"Math", "All Grades"}),
      do: StateComparison.for_filters(school_rows, [], filters).achievement[key]["PercentTested"]

    test "lower bound at least 95% meets it; 95%–97% meets it" do
      novice = perf("Novice", "0.5", grade: "All Grades")

      c = tested_cmp([novice, tested({"0.95", "0.97"})])
      assert %{status: :favorable, basis: :target} = c
      assert StateComparison.short_label(c) == "Meets 95% participation target"
      assert StateComparison.explanation(c) =~ "lower bound is at least 95%"
      assert StateComparison.explanation(c) =~ "not an official compliance finding"
      assert StateComparison.explanation(c) =~ "6311(c)(4)(E)"

      assert %{status: :favorable} = tested_cmp([novice, tested("0.95")])
      assert %{status: :favorable} = tested_cmp([novice, tested({"0.96", "1"})])
    end

    test "upper bound below 95% is below it; a range crossing 95% cannot be determined" do
      novice = perf("Novice", "0.5", grade: "All Grades")

      c = tested_cmp([novice, tested({"0.9", "0.94"})])
      assert %{status: :unfavorable} = c
      assert StateComparison.short_label(c) == "Below 95% participation target"
      assert %{status: :unfavorable} = tested_cmp([novice, tested("0.94")])

      c = tested_cmp([novice, tested({"0.9", "1"})])
      assert %{status: :inconclusive} = c
      assert StateComparison.short_label(c) == "Cannot determine (95% participation target)"
      assert StateComparison.explanation(c) =~ "crosses 95%"
    end

    test "no target for science, other assessment types, student groups or single grades" do
      science = [
        perf("Novice", "0.5", grade: "All Grades", subject: "Science"),
        tested("0.97", subject: "Science")
      ]

      c = tested_cmp(science, @filters, {"Science", "All Grades"})
      assert %{status: :neutral, reason: {:no_target, :subject}} = c
      assert StateComparison.explanation(c) =~ "not science"

      reg = [
        perf("Novice", "0.5", grade: "All Grades", assessment_type: "Reg"),
        tested("0.97", assessment_type: "Reg")
      ]

      assert %{reason: {:no_target, :assessment_type}} =
               tested_cmp(reg, %{@filters | type: "Reg"})

      female = [
        perf("Novice", "0.5", grade: "All Grades", subgroup: "Female"),
        tested("0.97", subgroup: "Female")
      ]

      assert %{reason: {:no_target, :subgroup}} =
               tested_cmp(female, %{@filters | subgroup: "Female"})

      grade6 = [perf("Novice", "0.5"), tested("0.97", grade: "6")]
      c = tested_cmp(grade6, @filters, {"Math", "6"})
      assert %{reason: {:no_target, :grade}} = c
      assert StateComparison.short_label(c) == "No participation target"
    end
  end

  test "All Grades coverage notes name both grade spans" do
    school = for grade <- ["6", "7", "8", "All Grades"], do: perf("Novice", "0.75", grade: grade)

    state =
      for grade <- ["3", "4", "5", "6", "7", "8", "All Grades"],
          do: perf("Novice", "0.28", grade: grade)

    compared = StateComparison.for_filters(school, state, @filters)

    assert [note] = StateComparison.coverage_notes(compared, :achievement)
    assert %{subject: "Math", school_grades: ~w(6 7 8), state_grades: ~w(3 4 5 6 7 8)} = note

    assert StateComparison.coverage_sentence(note) ==
             "Math All Grades is context only: this school's All Grades covers grades 6, 7, 8; North Dakota's covers 3, 4, 5, 6, 7, 8."
  end

  test "rows list every rated measure, including the growth percentile, with tone and reason" do
    p = &row(:growth_rate, "OverallGrowthPercentile", &1, unit: :percentile, grade: "7")
    compared = StateComparison.for_filters([p.("35")], [p.("50")], @filters)

    assert [row] = StateComparison.rows(compared)

    assert %{
             measure: "Overall growth percentile",
             school: "35",
             state: "50",
             status: :unfavorable,
             tone: :error,
             label: "Unfavorable vs ND"
           } = row

    assert row.explanation =~ "Higher Overall growth percentile is favorable"
  end
end
