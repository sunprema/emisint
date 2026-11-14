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

  defp perf(measure, v, overrides) do
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
    test "maps Oberon's metrics, with confirmations, no assumptions or grade references" do
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

  # The Standard (Reg) copies of the achievement rows.
  defp standard(rows) do
    for %{dataset: :assessment_performance} = r <- rows, do: Map.put(r, :assessment_type, "Reg")
  end

  describe "achievement" do
    test "workbook targets are compared in the Combined view (confirmed November 12, 2026)" do
      ela = goals(oberon_2324()).achievement[{"Reading", "All Grades"}]

      # Novice 50%–59% vs 18-month 29% (lower is better): above the target.
      assert %{status: :misses, code: "G1-M2", kind: :workbook} = ela["Novice"]
      assert ResultGoals.short_label(ela["Novice"]) == "Above target"
      assert ela["Novice"].target.text == "29%"
      assert ela["Novice"].value == "50%–59%"
      # Confirmed, not assumed: no "assumed" label, the confirmation is shown.
      assert ela["Novice"].assumed == []
      refute ela["Novice"].candidate?
      assert ela["Novice"].basis =~ "Confirmed by the user (November 12, 2026)"
      assert ResultGoals.explanation(ela["Novice"]) =~ "Combined assessment"
      # The baseline caveat is kept with the confirmation.
      assert ela["Novice"].basis =~ "baselines don't match the published state values"
      # 2023-24 predates the plan.
      assert ela["Novice"].timing == :before_plan
    end

    test "the Standard and Alternate views get no workbook verdict" do
      rows = oberon_2324() ++ standard(oberon_2324())

      reg = goals(rows, %{filters() | type: "Reg"}).achievement[{"Reading", "All Grades"}]
      refute Map.has_key?(reg, "Novice")
      refute Map.has_key?(reg, :proficient_or_advanced)

      config = ResultGoals.config(Oberon.school())
      assert config.confirmed.assessment_type == "Comp"

      assert ResultGoals.assessment_view_note(config, "Reg", true) ==
               "Workbook targets are compared only in the Combined assessment view (confirmed)."

      assert ResultGoals.assessment_view_note(config, "Comp", true) == nil
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
    test "Emotional Committed, Compliant and Disengaged are compared (confirmed November 12, 2026)" do
      emotional = goals(oberon_2324()).engagement[:engagement_emotional]

      # 2023-24 vs the 18-month range targets, by the dashboard range convention:
      # Committed 50%–59% vs 55-60%: overlaps; Compliant 30%–39% vs 50-55%:
      # misses; Disengaged 10%–19% vs 4-8% (lower is better): misses.
      assert %{code: "G4-M1", status: :overlaps} = emotional["Committed"]
      assert %{code: "G4-M2", status: :misses} = emotional["Compliant"]
      assert %{code: "G4-M3", status: :misses} = emotional["Disengaged"]

      for {_level, match} <- emotional do
        refute match.candidate?
        assert {:band, _, _} = match.spec
        # Confirmed population: not labeled as an assumption.
        assert match.assumed == []
        assert match.basis =~ "schoolwide, all-student Emotional"
        assert ResultGoals.explanation(match) =~ "dashboard comparison convention"
      end

      assert emotional["Committed"].target.text == "55-60%"

      [note | _] = ResultGoals.section_notes(:engagement, goals(oberon_2324()).engagement)
      assert note =~ "Confirmed by the user (November 12, 2026)"
      refute note =~ "Candidate"

      config = ResultGoals.config(Oberon.school())
      assert config.candidates == %{}
      assert config.confirmed.engagement_population == :schoolwide

      e36 = goals(oberon_2324(), filters(@y, :review_36m)).engagement[:engagement_emotional]
      # 50%–59% vs 60-65%: wholly below the low end, misses.
      assert %{status: :misses} = e36["Committed"]
      assert e36["Committed"].target.text == "60-65%"
    end

    test "the range convention is kept for when a mapping is confirmed" do
      d = &Decimal.new/1

      # 60%–69% vs 55-60% (higher is better): at or above the high end, meets.
      assert ResultGoals.classify_band(
               :higher_is_better,
               {d.("0.6"), d.("0.69")},
               d.("0.55"),
               d.("0.6")
             ) ==
               :meets

      # 50%–54% vs 50-55%: inside the range, overlaps; 30%–39% vs 50-55%: misses.
      assert ResultGoals.classify_band(
               :higher_is_better,
               {d.("0.5"), d.("0.54")},
               d.("0.5"),
               d.("0.55")
             ) ==
               :overlaps

      assert ResultGoals.classify_band(
               :higher_is_better,
               {d.("0.3"), d.("0.39")},
               d.("0.5"),
               d.("0.55")
             ) ==
               :misses

      # Lower is better: 0%–4% vs 4-8% meets; 10%–19% vs 4-8% misses.
      assert ResultGoals.classify_band(
               :lower_is_better,
               {d.("0"), d.("0.04")},
               d.("0.04"),
               d.("0.08")
             ) ==
               :meets

      assert ResultGoals.classify_band(
               :lower_is_better,
               {d.("0.1"), d.("0.19")},
               d.("0.04"),
               d.("0.08")
             ) ==
               :misses
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

      assert %{missing: "No matching results in the imported data"} =
               ResultGoals.annual(future, oberon_2324())
    end
  end
end
