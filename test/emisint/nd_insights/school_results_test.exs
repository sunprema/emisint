defmodule Emisint.NdInsights.SchoolResultsTest do
  use Emisint.DataCase, async: true

  import Emisint.ImprovementFixtures

  alias Emisint.NdInsights.{Importer, SchoolResults}

  @fixtures Path.expand("../../fixtures/nd_insights", __DIR__)
  @fort_yates "4300429212"

  setup do
    files = ~w(
      Insights-AssessmentPerformance-CSV-2023-2024-v20240824.csv
      Insights-AssessmentPerformance-CSV-2024-2025-v20251113.csv
      Insights-AssessmentParticipation-CSV-2024-2025-v20251113.csv
    )

    {:ok, _} =
      Importer.import_files(Enum.map(files, &Path.join(@fixtures, &1)),
        institution_ids: [@fort_yates]
      )

    {:ok, _} =
      Importer.import_files(
        [Path.join(@fixtures, "Insights-AssessmentPerformance-CSV-2099-2100-v20990101.csv")],
        institution_ids: ["TEST000001"]
      )

    viewer = user!(organization!(), :school_leader)

    %{
      state: SchoolResults.load(viewer, @fort_yates),
      synthetic: SchoolResults.load(viewer, "TEST000001")
    }
  end

  defp goal(year, subject, target, opts \\ []) do
    %{
      school_year: year,
      subject: subject,
      target_value: Decimal.new(target),
      measure: Keyword.get(opts, :measure, :proficient_or_advanced),
      includes_alternate: Keyword.get(opts, :includes_alternate, true)
    }
  end

  test "lists imported years newest first", %{state: state} do
    assert state.years == ["2024-2025", "2023-2024"]
  end

  test "derives Proficient or Advanced as an interval and keeps Proficient alone", %{state: state} do
    [reading] =
      state.rows
      |> SchoolResults.performance("2024-2025", "Comp", "All")
      |> Enum.filter(&(&1.subject == "Reading" and &1.grade == "All Grades"))

    # Proficient 20–29% + Advanced 0–10%
    assert {:ok, low, high} = reading.proficient_or_advanced
    assert Decimal.equal?(low, "0.2") and Decimal.equal?(high, "0.39")
    assert Decimal.equal?(reading.levels["Proficient"].range_high, "0.29")
    assert reading.tested.measure == "PercentTested"
  end

  test "goals with no published result for their year say so", %{state: state} do
    assert %{status: :not_published} =
             SchoolResults.compare_goal(goal("2025-2026", :ela, "0.25"), state.rows)
  end

  test "published ranges never produce a verdict, whatever the goal", %{state: state} do
    # 2024-25 Reading P+A = 20%–39% (both components are ranges)
    for target <- ~w(0.05 0.19 0.2 0.25 0.39 0.395 0.41 0.9) do
      assert %{
               status: :pending_range_clarification,
               derived: true,
               match: %{assessment_type: "Comp", grade: "All Grades", subgroup: "All"}
             } = SchoolResults.compare_goal(goal("2024-2025", :ela, target), state.rows)
    end

    # 2024-25 Math P+A = 0%–20%: even a goal far above the range gets no verdict.
    assert %{status: :pending_range_clarification, low: low, high: high} =
             SchoolResults.compare_goal(goal("2024-2025", :math, "0.37"), state.rows)

    assert Decimal.equal?(low, 0) and Decimal.equal?(high, "0.2")
  end

  describe "comparison boundaries (synthetic rows)" do
    defp row(measure, {:range, low, high}, overrides),
      do:
        base_row(
          measure,
          %{
            value_state: :range,
            range_low: Decimal.new(low),
            range_high: Decimal.new(high)
          },
          overrides
        )

    defp row(measure, {:exact, v}, overrides),
      do: base_row(measure, %{value_state: :exact, value: Decimal.new(v)}, overrides)

    defp base_row(measure, value, overrides) do
      %{
        dataset: :assessment_performance,
        academic_year: "2099-2100",
        subject: "Reading",
        grade: "All Grades",
        subgroup: "All",
        assessment_type: "Comp",
        accommodations: "All",
        measure: measure,
        value: nil,
        range_low: nil,
        range_high: nil
      }
      |> Map.merge(value)
      |> Map.merge(overrides)
    end

    defp compare(proficient, advanced, target, overrides \\ %{}, goal_opts \\ []) do
      rows = [row("Proficient", proficient, overrides), row("Advanced", advanced, overrides)]
      SchoolResults.compare_goal(goal("2099-2100", :ela, target, goal_opts), rows)
    end

    test "any range component means pending, even when the other is exact" do
      for {p, a} <- [
            {{:range, "0.2", "0.29"}, {:range, "0", "0.1"}},
            {{:exact, "0.30"}, {:range, "0", "0.1"}},
            {{:range, "0.2", "0.29"}, {:exact, "0.05"}}
          ],
          target <- ~w(0.1 0.2 0.35 0.5) do
        assert %{status: :pending_range_clarification} = compare(p, a, target)
      end
    end

    test "exact components are compared as published, with no rounding allowance" do
      # 30% + 5% = 35% exactly
      p = {:exact, "0.30"}
      a = {:exact, "0.05"}

      assert %{status: :meets, low: sum, high: sum} = compare(p, a, "0.35")
      assert Decimal.equal?(sum, "0.35")
      assert compare(p, a, "0.34").status == :meets
      assert compare(p, a, "0.351").status == :below
      assert compare(p, a, "0.36").status == :below
    end

    test "exact components still require year, population, assessment and measure to match" do
      p = {:exact, "0.30"}
      a = {:exact, "0.05"}

      for overrides <- [
            %{academic_year: "2098-2099"},
            %{subgroup: "Female"},
            %{grade: "7"},
            %{assessment_type: "Reg"},
            %{accommodations: "With Accommodations"},
            %{subject: "Math"},
            %{dataset: :assessment_participation}
          ] do
        assert %{status: :not_published} = compare(p, a, "0.35", overrides)
      end

      # A goal that excludes the alternate assessment only matches Standard rows.
      assert %{status: :not_published} = compare(p, a, "0.35", %{}, includes_alternate: false)

      assert %{status: :meets, match: %{assessment_type: "Reg"}} =
               compare(p, a, "0.35", %{assessment_type: "Reg"}, includes_alternate: false)

      # Another measure is never compared.
      assert %{status: :not_comparable} = compare(p, a, "0.35", %{}, measure: :proficient)
    end
  end

  describe "survey participation" do
    defp participation(level, low, high) do
      %{
        dataset: :engagement_participation,
        academic_year: "2099-2100",
        engagement_level: level,
        value_state: :range,
        value: nil,
        range_low: Decimal.new(low),
        range_high: Decimal.new(high)
      }
    end

    test "one value is shown only when every published row agrees; rows stay distinct" do
      rows =
        for level <- ~w(Disengaged Committed Compliant), do: participation(level, "0.95", "1.00")

      assert %{status: :consistent, result: result, rows: kept} =
               SchoolResults.survey_participation(rows, "2099-2100")

      assert Decimal.equal?(result.range_low, "0.95")
      assert Enum.map(kept, & &1.engagement_level) == ~w(Committed Compliant Disengaged)
    end

    test "rows that disagree are returned separately and not combined" do
      rows = [
        participation("Committed", "0.95", "1.00"),
        participation("Compliant", "0.90", "0.94"),
        participation("Disengaged", "0.95", "1.00")
      ]

      assert %{status: :inconsistent, rows: kept} =
               SchoolResults.survey_participation(rows, "2099-2100")

      assert length(kept) == 3
    end

    test "participation is not one of the engagement categories" do
      rows =
        for level <- ~w(Committed Compliant Disengaged), do: participation(level, "0.95", "1.00")

      assert SchoolResults.engagement(rows, "2099-2100") == []
      assert SchoolResults.survey_participation(rows, "2098-2099") == nil
    end
  end

  test "a suppressed component makes the measure not derivable", %{synthetic: synthetic} do
    assert %{status: :not_derivable, reason: "suppressed"} =
             SchoolResults.compare_goal(goal("2099-2100", :ela, "0.25"), synthetic.rows)
  end

  test "goals that exclude the alternate assessment compare with Standard, not Combined", %{
    state: state
  } do
    assert %{match: %{assessment_type: "Reg"}} =
             SchoolResults.compare_goal(
               goal("2024-2025", :ela, "0.25", includes_alternate: false),
               state.rows
             )
  end

  test "goals with another measure are never compared", %{state: state} do
    assert %{status: :not_comparable} =
             SchoolResults.compare_goal(
               goal("2024-2025", :ela, "0.25", measure: :proficient),
               state.rows
             )
  end
end
