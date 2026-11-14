defmodule Emisint.Improvement.GoalComparisonDecisionsTest do
  @moduledoc """
  The goal-comparison decisions of November 12, 2026:

    * Oberon: Combined assessment; schoolwide, all-student Emotional survey
      (see `oberon_result_goals_test.exs`).
    * Valley Middle: "Disengaged" → Overall Disengaged, "Engaged or
      Committed" → Overall Committed. Drayton: "Disengaged" → Overall
      Disengaged, "Engaged" → Overall Committed. Dunseith: "Disengaged" →
      Overall Disengaged. All confirmed.
    * Warwick: provisional dashboard reference assumptions (district rows,
      Combined, Proficient or Advanced for "proficiency"), relative targets
      as percentage-point changes from the workbook baseline; G2-M7 stays
      unresolved.
    * Cannon Ball: "demonstrate proficiency" → Proficient or Advanced and
      Combined (confirmed); math "expected annual growth" → Meets or Exceeds
      (provisional); single grades compared with their grade band's target
      as labeled references. Solen High School: the grade-10 goals on its own
      Grade 10 rows.

  Fort Yates is unchanged.
  """
  use ExUnit.Case, async: true

  alias Emisint.Improvement.ResultGoals
  alias Emisint.Improvement.Seeds

  defp plan(module, metrics_from \\ nil),
    do: %{
      school: module.school(),
      metrics: (metrics_from || module).metrics(),
      annual_goals: module.annual_assessment_goals()
    }

  defp filters(year, ref, type \\ "Comp"),
    do: %{year: year, type: type, subgroup: "All", reference: ref}

  defp value({low, high}),
    do: %{
      value_state: :range,
      value: nil,
      range_low: Decimal.new(low),
      range_high: Decimal.new(high)
    }

  defp value(v),
    do: %{value_state: :exact, value: Decimal.new(v), range_low: nil, range_high: nil}

  defp perf(year, subject, grade, measure, v, type \\ "Comp") do
    %{
      dataset: :assessment_performance,
      academic_year: year,
      subject: subject,
      grade: grade,
      subgroup: "All",
      assessment_type: type,
      accommodations: "All",
      measure: measure,
      unit: :proportion
    }
    |> Map.merge(value(v))
  end

  defp growth(year, subject, grade, measure, v) do
    %{
      dataset: :growth_rate,
      academic_year: year,
      subject: subject,
      grade: grade,
      subgroup: "All",
      measure: measure,
      unit: :proportion
    }
    |> Map.merge(value(v))
  end

  defp engagement(dataset, level, year, v),
    do:
      %{dataset: dataset, academic_year: year, engagement_level: level, unit: :proportion}
      |> Map.merge(value(v))

  defp goals(rows, f, plan), do: ResultGoals.for_filters(rows, f, plan)

  describe "confirmed engagement mappings (Valley, Drayton, Dunseith)" do
    test "Valley: G3-M1 → Overall Disengaged and G5-M2 → Overall Committed" do
      rows = [
        engagement(:engagement_overall, "Disengaged", "2024-2025", "0.18"),
        engagement(:engagement_overall, "Committed", "2024-2025", "0.3")
      ]

      overall =
        goals(rows, filters("2024-2025", :review_36m), plan(Seeds.ValleyMiddle)).engagement[
          :engagement_overall
        ]

      # 18% satisfies "< 22%", part of "< 22% or within 7% State Avg": meets.
      assert %{code: "G3-M1", status: :meets, candidate?: false} = overall["Disengaged"]
      # 30% vs "> 35%": misses.
      assert %{code: "G5-M2", status: :misses} = overall["Committed"]
      assert overall["Committed"].name == "G5-M2 Overall Committed"

      for {_level, m} <- overall do
        assert m.basis =~ "Confirmed by the user (November 12, 2026)"
        # Confirmed population: not labeled as an assumption.
        assert m.assumed == []
      end

      # 18-month targets: "n/a" and empty — gray, no target.
      m18 =
        goals(rows, filters("2024-2025", :review_18m), plan(Seeds.ValleyMiddle)).engagement[
          :engagement_overall
        ]

      assert %{status: :gray, reasons: [:no_target]} = m18["Disengaged"]
      assert %{status: :gray, reasons: [:no_target]} = m18["Committed"]
    end

    test "Drayton: G4-M1 → Overall Disengaged and G4-M2 (\"Engaged\") → Overall Committed" do
      rows = [
        engagement(:engagement_overall, "Disengaged", "2024-2025", {"0.25", "0.29"}),
        engagement(:engagement_overall, "Committed", "2024-2025", {"0.4", "0.44"})
      ]

      overall =
        goals(rows, filters("2024-2025", :review_36m), plan(Seeds.Drayton)).engagement[
          :engagement_overall
        ]

      # 25%–29% vs "< 18%": wholly above, misses; 40%–44% vs "> 39%": meets.
      assert %{code: "G4-M1", status: :misses} = overall["Disengaged"]
      assert ResultGoals.short_label(overall["Disengaged"]) == "Above target"
      assert %{code: "G4-M2", status: :meets} = overall["Committed"]
      assert overall["Committed"].basis =~ "InstitutionID 34019"

      [note | _] =
        ResultGoals.section_notes(
          :engagement,
          goals(rows, filters("2024-2025", :review_36m), plan(Seeds.Drayton)).engagement
        )

      assert note =~ "Confirmed by the user"
      refute note =~ "Candidate"
    end

    test "Dunseith: G6-M2 → Overall Disengaged" do
      rows = [engagement(:engagement_overall, "Disengaged", "2024-2025", "0.18")]

      overall =
        goals(rows, filters("2024-2025", :review_36m), plan(Seeds.Dunseith)).engagement[
          :engagement_overall
        ]

      # 18% vs "< 15%": misses.
      assert %{code: "G6-M2", status: :misses} = overall["Disengaged"]
      # Other areas have no Dunseith goal.
      rows = [engagement(:engagement_emotional, "Disengaged", "2024-2025", "0.18")]

      assert goals(rows, filters("2024-2025", :review_36m), plan(Seeds.Dunseith)).engagement[
               :engagement_emotional
             ] == %{}
    end
  end

  describe "Warwick: provisional, percentage-point targets" do
    defp warwick_rows(year \\ "2024-2025") do
      [
        perf(year, "Reading", "All Grades", "Novice", {"0.55", "0.59"}),
        perf(year, "Reading", "All Grades", "Proficient", {"0.05", "0.09"}),
        perf(year, "Reading", "All Grades", "Advanced", {"0", "0.04"}),
        perf(year, "Math", "All Grades", "Novice", {"0.4", "0.49"}),
        perf(year, "Math", "All Grades", "Proficient", {"0.1", "0.14"}),
        perf(year, "Math", "All Grades", "Advanced", {"0", "0.04"}),
        engagement(:engagement_emotional, "Disengaged", year, {"0.2", "0.24"}),
        engagement(:engagement_behavioral, "Committed", year, {"0.4", "0.44"})
      ]
    end

    test "relative targets become percentage-point bands from the workbook baseline" do
      g = goals(warwick_rows(), filters("2024-2025", :review_18m), plan(Seeds.Warwick))
      ela = g.achievement[{"Reading", "All Grades"}]
      math = g.achievement[{"Math", "All Grades"}]

      # ELA Novice baseline 59%, "Dec 2-3%" → 56%–57%; published 55%–59%: overlaps.
      assert %{code: "G3-M2", status: :overlaps} = ela["Novice"]
      assert ela["Novice"].target.text == "Dec 2-3% (56%–57%)"
      assert {:relative, "Dec", "2-3%", _, _, _} = ela["Novice"].spec

      assert ResultGoals.explanation(ela["Novice"]) =~
               "read as a 2-3% percentage-point decrease from the workbook baseline 59%, giving 56%–57%"

      # ELA proficiency rate = Proficient or Advanced: 5%–13% vs 7%–8% (Inc 2-3% from 5%): overlaps.
      assert %{code: "G3-M1", status: :overlaps, value: "5%–13%"} = ela[:proficient_or_advanced]
      assert ela[:proficient_or_advanced].target.text == "Inc 2-3% (7%–8%)"

      # Math Novice 40%–49% vs 72%–73% (Dec 2-3% from 75%): at or below the low end, meets.
      assert %{code: "G4-M2", status: :meets} = math["Novice"]
      # Math P+A 10%–18% vs 6%–7% (Inc 2-3% from 4%): at or above the high end, meets.
      assert %{code: "G4-M1", status: :meets} = math[:proficient_or_advanced]

      # Emotional Disengaged 20%–24% vs 22.74%–23.74% (Dec 2-3% from 25.74%): overlaps.
      emotional = g.engagement[:engagement_emotional]["Disengaged"]
      assert %{code: "G2-M6", status: :overlaps} = emotional
      assert emotional.target.text == "Dec 2-3% (22.74%–23.74%)"

      # 36-month: "Dec 4-6%" from 59% → 53%–55%.
      g36 = goals(warwick_rows(), filters("2024-2025", :review_36m), plan(Seeds.Warwick))

      assert g36.achievement[{"Reading", "All Grades"}]["Novice"].target.text ==
               "Dec 4-6% (53%–55%)"
    end

    test "every Warwick comparison is labeled provisional, with the assumptions" do
      g = goals(warwick_rows(), filters("2024-2025", :review_18m), plan(Seeds.Warwick))
      novice = g.achievement[{"Reading", "All Grades"}]["Novice"]

      assert novice.provisional?
      assert novice.assumed == [:combined_assessment]
      assert novice.basis =~ "Provisional dashboard reference assumption"
      assert ResultGoals.goal_line(novice) =~ "· provisional"
      assert ResultGoals.explanation(novice) =~ "doesn't record a review result"

      [note | _] = ResultGoals.section_notes(:achievement, g.achievement)
      assert note =~ "Combined assessment assumed for workbook targets (provisional)"

      [enote | _] = ResultGoals.section_notes(:engagement, g.engagement)
      assert enote =~ "schoolwide survey population match assumed (provisional)"

      config = ResultGoals.config(Seeds.Warwick.school())

      assert ResultGoals.assessment_view_note(config, "Reg", true) ==
               "Workbook targets are compared only in the Combined assessment view (provisional assumption)."

      # The Standard view gets no workbook verdict.
      reg =
        goals(
          Enum.map(warwick_rows(), &Map.put(&1, :assessment_type, "Reg")),
          filters("2024-2025", :review_18m, "Reg"),
          plan(Seeds.Warwick)
        )

      assert reg.achievement[{"Reading", "All Grades"}] == %{}
    end

    test "G2-M7 (behaviorally committed, \"Dec\") and the special-education goals stay unresolved" do
      g = goals(warwick_rows(), filters("2024-2025", :review_18m), plan(Seeds.Warwick))
      assert g.engagement[:engagement_behavioral] == %{}

      codes = Enum.map(ResultGoals.config(Seeds.Warwick.school()).workbook, &elem(&1, 0))
      refute "G2-M7" in codes
      refute "G5-M3" in codes
      refute "G5-M4" in codes

      assert ResultGoals.config(Seeds.Warwick.school()).section_notes.engagement =~
               "unresolved until Ram confirms its direction"
    end

    test "a relative target against the metric's direction is gray, and no rule means not comparable" do
      metric = %{
        unit: :percent,
        direction: :higher_is_better,
        baseline_value: Decimal.new("0.4698"),
        flags: [],
        target_18m: nil,
        source_values: %{"target_18m" => %{"cell" => "W!H17", "raw" => "Dec 2-3%"}}
      }

      assert {:relative, "Dec", "2-3%", _, low, high} =
               ResultGoals.target_spec(metric, :target_18m, :percentage_points)

      assert Decimal.equal?(low, "0.4398") and Decimal.equal?(high, "0.4498")
      assert ResultGoals.target_spec(metric, :target_18m) == :not_comparable

      assert ResultGoals.target_spec(
               %{metric | baseline_value: nil},
               :target_18m,
               :percentage_points
             ) == :not_comparable
    end
  end

  describe "Cannon Ball: grade-group references" do
    defp cannon_ball_rows do
      [
        perf("2023-2024", "Reading", "All Grades", "Novice", {"0.7", "0.74"}),
        perf("2023-2024", "Reading", "All Grades", "Proficient", {"0.1", "0.14"}),
        perf("2023-2024", "Reading", "All Grades", "Advanced", {"0", "0.04"}),
        perf("2023-2024", "Reading", "4", "Novice", {"0.4", "0.49"}),
        perf("2023-2024", "Reading", "4", "Proficient", {"0", "0.2"}),
        perf("2023-2024", "Reading", "4", "Advanced", {"0", "0.2"}),
        perf("2023-2024", "Reading", "7", "Novice", {"0.6", "0.69"}),
        perf("2023-2024", "Math", "8", "Novice", {"0.8", "1"}),
        perf("2023-2024", "Math", "10", "Novice", {"0.8", "1"}),
        growth("2023-2024", "Math", "4", "Meets", {"0.3", "0.39"}),
        growth("2023-2024", "Math", "4", "Exceeds", {"0", "0.2"}),
        growth("2023-2024", "Math", "6", "Meets", {"0.5", "0.59"}),
        growth("2023-2024", "Math", "6", "Exceeds", {"0", "0.2"}),
        growth("2023-2024", "ELA", "4", "Meets", {"0.3", "0.39"}),
        growth("2023-2024", "ELA", "4", "Exceeds", {"0", "0.2"})
      ]
    end

    test "each grade is compared with its band's target, labeled as a reference" do
      g = goals(cannon_ball_rows(), filters("2023-2024", :review_18m), plan(Seeds.CannonBall))
      g4 = g.achievement[{"Reading", "4"}]

      # Grade 4 Reading Novice 40%–49% vs G1-M4 (grades 3–5) 39%: above.
      assert %{
               kind: :grade_group_reference,
               code: "G1-M4",
               group: "grades 3–5",
               grade: "4",
               status: :misses
             } =
               g4["Novice"]

      assert ResultGoals.short_label(g4["Novice"]) == "Above grades 3–5 target"

      assert ResultGoals.goal_line(g4["Novice"]) =~
               "Grades 3–5 target: 39% · 18-month · G1-M4 · Grade-group reference"

      explanation = ResultGoals.explanation(g4["Novice"])

      assert explanation =~
               "Grade 4 compared with the G1-M4 target for grades 3–5, for reference only"

      assert explanation =~ "not the grades 3–5 result"
      assert explanation =~ "never averaged"

      # "Demonstrate proficiency" = Proficient or Advanced (derived 0%–40%) vs 18%: overlaps.
      assert %{code: "G1-M1", status: :overlaps, value: "0%–40%"} = g4[:proficient_or_advanced]

      assert ResultGoals.short_label(g4[:proficient_or_advanced]) ==
               "Range overlaps grades 3–5 target"

      assert g4[:proficient_or_advanced].basis =~ "Proficient or Advanced"

      # Grades 6–8 use the grades 6–8 targets: Reading grade 7 vs G1-M5 41%; Math grade 8 vs G2-M5.
      assert %{code: "G1-M5", group: "grades 6–8", status: :misses} =
               g.achievement[{"Reading", "7"}]["Novice"]

      assert %{code: "G2-M5", group: "grades 6–8"} = g.achievement[{"Math", "8"}]["Novice"]

      # Grade 10 isn't Cannon Ball's: no goal here (it is Solen High School's).
      assert g.achievement[{"Math", "10"}] == %{}
    end

    test "the All Grades row is never presented as a grade band's result" do
      g = goals(cannon_ball_rows(), filters("2023-2024", :review_18m), plan(Seeds.CannonBall))
      all = g.achievement[{"Reading", "All Grades"}]

      refute Enum.any?(Map.values(all), &(&1.kind in [:workbook, :grade_group_reference]))

      [_ | _] = notes = ResultGoals.section_notes(:achievement, g.achievement)
      assert Enum.any?(notes, &(&1 =~ "A single grade's result is not the grade group's result"))
      assert Enum.any?(notes, &(&1 =~ "never averaged into one"))
    end

    test "math growth: Meets or Exceeds against the band target, provisional" do
      g = goals(cannon_ball_rows(), filters("2023-2024", :review_18m), plan(Seeds.CannonBall))

      # Grade 4: Meets 30%–39% + Exceeds 0%–20% = 30%–59% vs G2-M1 25%: meets.
      m4 = g.growth[{"Math", "4"}][:meets_or_exceeds]
      assert %{kind: :grade_group_reference, code: "G2-M1", status: :meets, value: "30%–59%"} = m4
      assert m4.provisional?
      assert ResultGoals.short_label(m4) == "At or above grades 3–5 target"
      assert ResultGoals.goal_line(m4) =~ "· provisional"
      assert m4.basis =~ "Provisional, for dashboard reference"

      # Grade 6 vs G2-M2 18%: 50%–79%, meets.
      assert %{code: "G2-M2", status: :meets} = g.growth[{"Math", "6"}][:meets_or_exceeds]

      # ELA growth has no school goal.
      assert g.growth[{"ELA", "4"}] == %{}

      [note | _] = ResultGoals.section_notes(:growth, g.growth)
      assert note =~ "Provisional mapping for dashboard reference"
    end

    test "Combined is confirmed: the Standard view gets no workbook comparison" do
      rows = Enum.map(cannon_ball_rows(), &Map.put(&1, :assessment_type, "Reg"))
      g = goals(rows, filters("2023-2024", :review_18m, "Reg"), plan(Seeds.CannonBall))
      assert g.achievement[{"Reading", "4"}] == %{}

      config = ResultGoals.config(Seeds.CannonBall.school())

      assert ResultGoals.assessment_view_note(config, "Reg", true) ==
               "Workbook targets are compared only in the Combined assessment view (confirmed)."
    end
  end

  describe "Solen High School: the grade-10 goals on its own Grade 10 rows" do
    defp solen_rows do
      for grade <- ["10", "All Grades"],
          {subject, novice} <- [{"Reading", {"0.7", "0.79"}}, {"Math", {"0.8", "1"}}],
          {measure, v} <- [
            {"Novice", novice},
            {"Proficient", {"0", "0.2"}},
            {"Advanced", {"0", "0.2"}}
          ],
          do: perf("2023-2024", subject, grade, measure, v)
    end

    test "Grade 10 is the goal's own group, labeled by grade" do
      plan = plan(Seeds.SolenHigh, Seeds.CannonBall)
      g = goals(solen_rows(), filters("2023-2024", :review_18m), plan)
      reading = g.achievement[{"Reading", "10"}]

      # G1-M3: Proficient or Advanced 0%–40% vs 20%: overlaps.
      assert %{kind: :workbook, code: "G1-M3", grade: "10", status: :overlaps} =
               reading[:proficient_or_advanced]

      assert reading[:proficient_or_advanced].name ==
               "G1-M3 Grade 10 Reading Proficient or Advanced"

      assert ResultGoals.goal_line(reading[:proficient_or_advanced]) =~
               "Grade 10 Reading Proficient or Advanced"

      # G1-M6 Reading Novice 70%–79% vs 15%: above. G2-M6 Math Novice 80%–100% vs 68%: above.
      assert %{code: "G1-M6", status: :misses} = reading["Novice"]
      assert %{code: "G2-M6", status: :misses} = g.achievement[{"Math", "10"}]["Novice"]
      assert reading["Novice"].basis =~ "Confirmed by the user (November 12, 2026)"

      # The All Grades row (the same grade-10 students) isn't compared.
      assert g.achievement[{"Reading", "All Grades"}] == %{}

      config = ResultGoals.config(Seeds.SolenHigh.school())
      assert config.workbook_from == Seeds.CannonBall
      assert config.section_notes.growth =~ "no growth rows"
    end

    test "without Cannon Ball's metrics there is nothing to compare" do
      g = goals(solen_rows(), filters("2023-2024", :review_18m), plan(Seeds.SolenHigh))
      assert g.achievement[{"Reading", "10"}] == %{}
    end
  end

  describe "Fort Yates is unchanged" do
    test "demo assumptions are still labeled as assumed" do
      config = ResultGoals.config(Seeds.FortYates.school())
      assert config.assumptions == %{assessment_type: "Comp", engagement_population: :schoolwide}
      assert config.confirmed == %{}
      assert config.provisional == %{}
      assert config.relative_targets == nil

      rows = [
        perf("2024-2025", "Reading", "All Grades", "Proficient", {"0.1", "0.14"}),
        engagement(:engagement_emotional, "Disengaged", "2024-2025", {"0.2", "0.24"})
      ]

      g = goals(rows, filters("2024-2025", :review_18m), plan(Seeds.FortYates))
      prof = g.achievement[{"Reading", "All Grades"}]["Proficient"]
      assert prof.assumed == [:combined_assessment]
      refute prof.provisional?
      refute ResultGoals.goal_line(prof) =~ "provisional"

      assert g.engagement[:engagement_emotional]["Disengaged"].assumed == [:schoolwide_survey]

      assert ResultGoals.assessment_view_note(config, "Reg", true) ==
               "Workbook targets are compared only in the Combined assessment view (demo assumption)."

      [note | _] = ResultGoals.section_notes(:achievement, g.achievement)
      assert note == "Reference comparison; Combined assessment assumed for workbook targets."
    end
  end
end
