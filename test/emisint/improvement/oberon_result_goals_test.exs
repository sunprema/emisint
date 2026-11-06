defmodule Emisint.Improvement.OberonResultGoalsTest do
  use ExUnit.Case, async: true

  alias Emisint.Improvement.ResultGoals
  alias Emisint.Improvement.Seeds.{FortYates, Oberon}

  @y "2023-2024"

  defp plan do
    %{
      school: Oberon.school(),
      metrics: Oberon.metrics(),
      annual_goals: Oberon.annual_assessment_goals()
    }
  end

  defp filters(year \\ @y, ref \\ :review_18m),
    do: %{year: year, type: "Comp", subgroup: "All", reference: ref}

  defp value({:exact, v}), do: %{value_state: :exact, value: Decimal.new(v)}

  defp value({:range, low, high}),
    do: %{value_state: :range, range_low: Decimal.new(low), range_high: Decimal.new(high)}

  defp perf(measure, v, overrides \\ %{}) do
    %{
      dataset: :assessment_performance,
      academic_year: @y,
      subject: "Reading",
      grade: "All Grades",
      subgroup: "All",
      assessment_type: "Comp",
      accommodations: "All",
      measure: measure,
      unit: :proportion,
      value: nil,
      range_low: nil,
      range_high: nil
    }
    |> Map.merge(value(v))
    |> Map.merge(overrides)
  end

  defp engagement(dataset, level, low, high) do
    %{
      dataset: dataset,
      academic_year: @y,
      engagement_level: level,
      unit: :proportion,
      value: nil,
      range_low: nil,
      range_high: nil
    }
    |> Map.merge(value({:range, low, high}))
  end

  # Oberon's published 2023-24 values (Combined, All Grades, all students).
  defp oberon_2324(overrides \\ %{}) do
    [
      perf("Novice", {:range, "0.5", "0.59"}, overrides),
      perf("Proficient", {:range, "0.2", "0.29"}, overrides),
      perf("Advanced", {:range, "0", "0.1"}, overrides),
      perf("Novice", {:range, "0.4", "0.49"}, Map.put(overrides, :subject, "Math")),
      perf("Proficient", {:range, "0.2", "0.29"}, Map.put(overrides, :subject, "Math")),
      perf("Advanced", {:range, "0", "0.1"}, Map.put(overrides, :subject, "Math")),
      engagement(:engagement_emotional, "Committed", "0.5", "0.59"),
      engagement(:engagement_emotional, "Compliant", "0.3", "0.39"),
      engagement(:engagement_emotional, "Disengaged", "0.1", "0.19"),
      engagement(:engagement_behavioral, "Disengaged", "0.1", "0.19")
    ]
  end

  defp goals(rows, f \\ filters(), opts \\ []), do: ResultGoals.for_filters(rows, f, plan(), opts)

  describe "Oberon's own comparison configuration" do
    test "maps Oberon's metrics, with no assumptions or grade references" do
      config = ResultGoals.config(Oberon.school())

      assert Enum.map(config.workbook, &elem(&1, 0)) ==
               ~w(G1-M1 G1-M2 G2-M1 G2-M2 G4-M1 G4-M2 G4-M3)

      assert config.assumptions == %{}
      assert config.grade_reference == nil
      assert config.plan_start_year == "2025-2026"
    end

    test "Fort Yates keeps its own mapping and demo assumptions" do
      config = ResultGoals.config(FortYates.school())

      assert Enum.map(config.workbook, &elem(&1, 0)) ==
               ~w(G2-M1 G2-M2 G3-M1 G3-M2 G2-M3 G3-M3 G4-M2 G4-M3 G4-M4)

      assert config.assumptions == %{assessment_type: "Comp", engagement_population: :schoolwide}
      assert config.grade_reference.grades == ~w(6 7 8)
      assert ResultGoals.demo_assumptions() == config.assumptions
    end

    test "a school without a definition module gets no workbook match" do
      school = %{Oberon.school() | state_entity_id: "0000000000"}
      rows = oberon_2324()
      g = ResultGoals.for_filters(rows, filters(), %{plan() | school: school})

      # Only the annual target (from the plan's own goals) remains.
      assert Map.keys(g.achievement[{"Reading", "All Grades"}]) == [:proficient_or_advanced]
      assert g.engagement[:engagement_emotional] == %{}
      assert ResultGoals.config(school).workbook == []
    end
  end

  describe "achievement" do
    test "workbook targets stay gray: the assessment behind them isn't confirmed" do
      ela = goals(oberon_2324()).achievement[{"Reading", "All Grades"}]

      assert %{status: :gray, reasons: [:assessment_type_unconfirmed], code: "G1-M2"} =
               ela["Novice"]

      assert ResultGoals.short_label(ela["Novice"]) == "Gray: assessment type unconfirmed"
      # 2023-24 predates the plan.
      assert ela["Novice"].timing == :before_plan
    end

    test "the same-year annual target takes the Proficient-or-Advanced cell" do
      ela = goals(oberon_2324()).achievement[{"Reading", "All Grades"}]

      # 20%–39% derived vs the 2023-24 annual target 22%.
      assert %{kind: :annual, status: :overlaps} = ela[:proficient_or_advanced]
      assert ela[:proficient_or_advanced].target.text == "22%"
    end

    test "without an annual target, G1-M1 compares the derived Proficient or Advanced" do
      rows = oberon_2324(%{academic_year: "2024-2025"})
      opts = [assumptions: %{assessment_type: "Comp"}]

      ela = goals(rows, filters("2024-2025"), opts).achievement[{"Reading", "All Grades"}]
      math = goals(rows, filters("2024-2025"), opts).achievement[{"Math", "All Grades"}]

      # 20%–39% vs 18-month 23%: overlaps; Novice 50%–59% vs 29% (lower is better): misses.
      assert %{kind: :workbook, code: "G1-M1", status: :overlaps, value: "20%–39%"} =
               ela[:proficient_or_advanced]

      assert %{code: "G1-M2", status: :misses} = ela["Novice"]
      # Math: 20%–39% vs 11%: meets; Novice 40%–49% vs 58%: meets.
      assert %{code: "G2-M1", status: :meets} = math[:proficient_or_advanced]
      assert %{code: "G2-M2", status: :meets} = math["Novice"]

      ela36 =
        goals(rows, filters("2024-2025", :review_36m), opts).achievement[
          {"Reading", "All Grades"}
        ]

      assert ela36[:proficient_or_advanced].target.text == "30%"
      assert ela36["Novice"].target.text == "22%"
    end

    test "Fort Yates's Proficient-alone codes never apply to Oberon" do
      math = goals(oberon_2324()).achievement[{"Math", "All Grades"}]

      refute Map.has_key?(math, "Proficient")
      refute Enum.any?(Map.values(math), &(&1.code in ~w(G3-M1 G3-M2)))
    end

    test "grade rows get no reference colors" do
      rows = oberon_2324(%{grade: "4"})
      g = goals(rows, filters(), assumptions: %{assessment_type: "Comp"})

      assert g.achievement[{"Reading", "4"}] == %{}
    end
  end

  describe "engagement" do
    test "Emotional Committed, Compliant and Disengaged map to G4-M1..M3, gray for range targets" do
      emotional = goals(oberon_2324()).engagement[:engagement_emotional]

      for {level, code} <- [
            {"Committed", "G4-M1"},
            {"Compliant", "G4-M2"},
            {"Disengaged", "G4-M3"}
          ] do
        assert %{code: ^code, status: :gray, reasons: [:target_is_range]} = emotional[level]
        assert ResultGoals.short_label(emotional[level]) == "Gray: target is a range"
      end

      assert emotional["Committed"].target.text == "55-60%"
      assert emotional["Disengaged"].direction == :lower_is_better
      assert ResultGoals.explanation(emotional["Committed"]) =~ "written as a range"
    end

    test "other domains have no Oberon goal" do
      assert goals(oberon_2324()).engagement[:engagement_behavioral] == %{}
    end
  end

  describe "wording" do
    test "the methodology is Oberon's own" do
      text = ResultGoals.config(Oberon.school()) |> ResultGoals.methodology() |> Enum.join(" ")

      assert text =~ "G1-M1 ELA, G2-M1 Math"
      assert text =~ "No assumptions are applied for Oberon"
      refute text =~ "Fort Yates"
      refute text =~ "G2-M3 (ELA)"
      assert ResultGoals.methodology() |> Enum.join(" ") =~ "G2-M3 (ELA) and G3-M3 (Math)"
    end

    test "annual years: goals that ended earlier or start later" do
      years = Enum.map(Oberon.annual_assessment_goals(), & &1.school_year)

      assert ResultGoals.annual_years_note(years, "2024-2025") =~ "end in 2023-2024"

      assert ResultGoals.annual_years_note(~w(2025-2026 2030-2031), "2024-2025") =~
               "start in 2025-2026"
    end

    test "a past annual target with no imported download says so" do
      goal = Enum.find(Oberon.annual_assessment_goals(), &(&1.school_year == "2018-2019"))

      assert %{status: :not_published, missing: "No result imported"} =
               ResultGoals.annual(goal, oberon_2324())

      future = %{goal | school_year: "2030-2031"}
      assert %{missing: "Not yet published"} = ResultGoals.annual(future, oberon_2324())
    end
  end
end
