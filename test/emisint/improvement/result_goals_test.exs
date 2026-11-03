defmodule Emisint.Improvement.ResultGoalsTest do
  use ExUnit.Case, async: true

  alias Emisint.Improvement.ResultGoals
  alias Emisint.Improvement.Seeds.FortYates

  @year "2025-2026"
  @filters %{year: @year, type: "Comp", subgroup: "All"}
  # Lets workbook achievement targets be compared (the assessment type
  # isn't established for the real plan).
  @type_known [established: %{assessment_type: "Comp"}]

  defp plan(school \\ FortYates.school()) do
    %{
      school: school,
      metrics: FortYates.metrics(),
      annual_goals: FortYates.annual_assessment_goals()
    }
  end

  defp value({:exact, v}), do: %{value_state: :exact, value: Decimal.new(v)}

  defp value({:range, low, high}),
    do: %{value_state: :range, range_low: Decimal.new(low), range_high: Decimal.new(high)}

  defp value(:suppressed), do: %{value_state: :suppressed}

  defp perf(measure, v, overrides \\ %{}) do
    %{
      dataset: :assessment_performance,
      academic_year: @year,
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

  defp growth(v, overrides \\ %{}) do
    perf("OverallGrowthPercentile", v, %{dataset: :growth_rate, subject: "ELA", unit: :percentile})
    |> Map.merge(overrides)
  end

  defp engagement(level, v) do
    %{
      dataset: :engagement_emotional,
      academic_year: @year,
      engagement_level: level,
      unit: :proportion,
      value: nil,
      range_low: nil,
      range_high: nil
    }
    |> Map.merge(value(v))
  end

  defp match(rows, section, key, measure, opts \\ [], filters \\ @filters, plan \\ plan()) do
    rows |> ResultGoals.for_filters(filters, plan, opts) |> get_in([section, key, measure])
  end

  defp ela(rows, measure, opts \\ [], filters \\ @filters),
    do: match(rows, :achievement, {"Reading", "All Grades"}, measure, opts, filters)

  defp gp(v, opts \\ [], filters \\ @filters),
    do:
      match([growth(v)], :growth, {"ELA", "All Grades"}, "OverallGrowthPercentile", opts, filters)

  describe "the dashboard comparison rule" do
    test "higher is better: lower bound at or above meets, upper bound below misses, else overlaps" do
      # G2-M3 18-month target 43 (a growth percentile).
      assert gp({:exact, "43"}).status == :meets, "equality meets"
      assert gp({:exact, "50"}).status == :meets
      assert gp({:range, "43", "50"}).status == :meets
      assert %{status: :misses, tone: :error} = m = gp({:exact, "42.5"})
      assert ResultGoals.short_label(m) == "Below target"
      assert gp({:range, "30", "42.9"}).status == :misses
      assert %{status: :overlaps, tone: :warning} = o = gp({:range, "40", "45"})
      assert ResultGoals.short_label(o) == "Range overlaps target"
      # Higher is better: a range ending exactly on the target overlaps (it
      # includes values below). Lower is better is the mirror image; see the
      # boundary tests below.
      assert gp({:range, "40", "43"}).status == :overlaps
    end

    test "lower is better: upper bound at or below meets, lower bound above misses, else overlaps" do
      # G2-M2 ELA Novice, 18-month target 39%.
      novice = &ela([perf("Novice", &1)], "Novice", @type_known)

      assert novice.({:exact, "0.39"}).status == :meets, "equality meets"
      assert novice.({:range, "0.3", "0.39"}).status == :meets
      assert %{status: :misses} = above = novice.({:range, "0.40", "0.49"})
      assert ResultGoals.short_label(above) == "Above target"
      assert novice.({:exact, "0.391"}).status == :misses
      assert novice.({:range, "0.35", "0.45"}).status == :overlaps
      assert novice.({:range, "0.39", "0.45"}).status == :overlaps
      assert ResultGoals.goal_line(above) =~ "lower is better"
    end

    test "the selected reference checkpoint decides the target" do
      m = gp({:exact, "50"}, [], Map.put(@filters, :reference, :review_36m))
      assert m.target == %{label: "36-month target", text: "51"}
      assert m.status == :misses
      assert ResultGoals.reference("36m") == :review_36m
      assert ResultGoals.reference(nil) == :review_18m
    end

    test "growth percentiles keep their unit: no percent signs" do
      m = gp({:exact, "38"})

      assert ResultGoals.goal_line(m) ==
               "2025-2026 result · Growth percentile target: 43 · 18-month · G2-M3"

      refute ResultGoals.explanation(m) =~ "%"
    end

    test "the explanation states the rule is not official and has no effect on reviews or payment" do
      text = ResultGoals.explanation(gp({:exact, "38"}))
      assert text =~ "not an official ND FIRST scoring method"
      assert text =~ "doesn't record a review result, set a rating or affect the payment estimate"
    end

    test "missing and suppressed values are gray with the reason" do
      assert %{status: :gray, tone: :muted} = s = gp(:suppressed)
      assert ResultGoals.short_label(s) == "Gray: suppressed"
      # The target is still shown.
      assert ResultGoals.goal_line(s) =~ "Growth percentile target: 43 · 18-month"
    end
  end

  describe "matching goals" do
    test "Proficient alone matches the workbook Proficient goal, never Proficient or Advanced" do
      rows = [perf("Proficient", {:exact, "0.27"}), perf("Advanced", {:exact, "0.05"})]

      by =
        ResultGoals.for_filters(rows, @filters, plan(), @type_known).achievement[
          {"Reading", "All Grades"}
        ]

      assert %{code: "G2-M1", status: :meets, target: %{text: "27%"}} = by["Proficient"]
      # 27% + 5% = 32% is compared with the annual target (25%), not G2-M1.
      assert %{kind: :annual, value: "32%", target: %{text: "25%"}} = by[:proficient_or_advanced]
      refute Map.has_key?(by, "Partially")
      refute Map.has_key?(by, "Advanced")
    end

    test "demo assumption: workbook achievement targets count the Combined assessment" do
      rows = [perf("Proficient", {:exact, "0.30"}), perf("Advanced", {:exact, "0.05"})]

      combined = ResultGoals.for_filters(rows, @filters, plan()).achievement
      m = combined[{"Reading", "All Grades"}]["Proficient"]
      assert %{status: :meets, assumed: [:combined_assessment]} = m

      # Standard and Alternate views get no workbook verdict (nor the annual
      # target, which counts the Combined assessment).
      for type <- ~w(Reg Alt) do
        typed = Enum.map(rows, &%{&1 | assessment_type: type})
        by = ResultGoals.for_filters(typed, %{@filters | type: type}, plan()).achievement
        assert by[{"Reading", "All Grades"}] == %{}
      end

      # Without the assumption the comparison is gray, and only that one.
      rows = rows ++ [growth({:exact, "50"})]
      goals = ResultGoals.for_filters(rows, @filters, plan(), assumptions: %{})
      gray = goals.achievement[{"Reading", "All Grades"}]["Proficient"]
      assert %{status: :gray, reasons: [:assessment_type_unconfirmed]} = gray
      assert ResultGoals.short_label(gray) == "Gray: assessment type unconfirmed"

      assert goals.achievement[{"Reading", "All Grades"}][:proficient_or_advanced].status ==
               :meets

      assert goals.growth[{"ELA", "All Grades"}]["OverallGrowthPercentile"].status == :meets
    end

    test "demo assumption: engagement targets count the schoolwide survey population" do
      rows = [
        engagement("Disengaged", {:exact, "0.30"}),
        engagement("Committed", {:exact, "0.5"})
      ]

      by = ResultGoals.for_filters(rows, @filters, plan()).engagement[:engagement_emotional]
      # G4-M2 18-month target 32.9%; 30% is at or below (lower is better).
      assert %{code: "G4-M2", status: :meets, assumed: [:schoolwide_survey]} = by["Disengaged"]
      # G4-M1 (observed active engagement) is never matched to survey Committed.
      refute Map.has_key?(by, "Committed")

      off = ResultGoals.for_filters(rows, @filters, plan(), assumptions: %{})

      assert %{status: :gray, reasons: [:population_unverified]} =
               off.engagement[:engagement_emotional]["Disengaged"]
    end

    test "schoolwide goals never apply to a single grade or a student group" do
      rows = [perf("Proficient", {:exact, "0.30"}, %{grade: "7"})]
      # A grade row gets only a schoolwide reference, never its own goal.
      assert %{kind: :grade_reference} =
               match(rows, :achievement, {"Reading", "7"}, "Proficient", @type_known)

      g = growth({:exact, "60"}, %{grade: "7"})

      assert %{kind: :grade_reference} =
               match([g], :growth, {"ELA", "7"}, "OverallGrowthPercentile")

      female = %{@filters | subgroup: "Female"}
      g = growth({:exact, "60"}, %{subgroup: "Female"})
      assert ResultGoals.for_filters([g], female, plan()).growth[{"ELA", "All Grades"}] == %{}
    end

    test "workbook goals belong to Fort Yates only" do
      other = %{FortYates.school() | state_entity_id: "0000000000"}

      assert match(
               [growth({:exact, "50"})],
               :growth,
               {"ELA", "All Grades"},
               "OverallGrowthPercentile",
               [],
               @filters,
               plan(other)
             ) == nil
    end
  end

  describe "timing" do
    test "a result from before the plan began is a reference comparison against a future target" do
      rows = [growth({:exact, "38"}, %{academic_year: "2024-2025"})]

      m =
        match(rows, :growth, {"ELA", "All Grades"}, "OverallGrowthPercentile", [], %{
          @filters
          | year: "2024-2025"
        })

      assert %{timing: :before_plan, status: :misses} = m
      assert ResultGoals.timing_label(m) == "Reference comparison against future target"

      assert ResultGoals.goal_line(m) =~
               "2024-2025 result · Growth percentile target: 43 · 18-month"
    end

    test "with no confirmed review year, a plan-period result says so" do
      m = gp({:exact, "50"})
      assert m.timing == :unconfirmed
      assert ResultGoals.timing_label(m) == "Reference comparison — review year unconfirmed"
    end

    test "with an established review year, only that year is a same-year comparison" do
      opts = [established: %{review_years: %{review_18m: "2026-2027"}}]
      earlier = gp({:exact, "50"}, opts)
      assert earlier.timing == {:before_review, "2026-2027"}
      assert ResultGoals.timing_label(earlier) == "Reference comparison against future target"

      same =
        match(
          [growth({:exact, "50"}, %{academic_year: "2026-2027"})],
          :growth,
          {"ELA", "All Grades"},
          "OverallGrowthPercentile",
          opts,
          %{@filters | year: "2026-2027"}
        )

      assert same.timing == :same_year
      assert ResultGoals.timing_label(same) == nil
    end
  end

  describe "annual targets" do
    test "compare only with the same school year, Combined assessment" do
      exact = [perf("Proficient", {:exact, "0.20"}), perf("Advanced", {:exact, "0.05"})]
      assert %{status: :meets, timing: :same_year} = ela(exact, :proficient_or_advanced)

      ranged = [
        perf("Proficient", {:range, "0.2", "0.29"}),
        perf("Advanced", {:range, "0", "0.1"})
      ]

      assert ela(ranged, :proficient_or_advanced).status == :overlaps

      above = [perf("Proficient", {:range, "0.3", "0.39"}), perf("Advanced", {:exact, "0"})]
      assert ela(above, :proficient_or_advanced).status == :meets

      below = [perf("Proficient", {:range, "0", "0.1"}), perf("Advanced", {:range, "0", "0.1"})]
      assert ela(below, :proficient_or_advanced).status == :misses

      reg = Enum.map(exact, &%{&1 | assessment_type: "Reg"})
      assert ela(reg, :proficient_or_advanced, [], %{@filters | type: "Reg"}) == nil
    end

    test "another year's annual target is never substituted" do
      rows =
        Enum.map(
          [perf("Proficient", {:exact, "0.20"}), perf("Advanced", {:exact, "0.05"})],
          &%{&1 | academic_year: "2024-2025"}
        )

      assert ela(rows, :proficient_or_advanced, [], %{@filters | year: "2024-2025"}) == nil
    end

    test "a suppressed component is gray" do
      rows = [perf("Proficient", :suppressed), perf("Advanced", {:exact, "0.05"})]
      assert %{status: :gray, reasons: [:not_derivable]} = ela(rows, :proficient_or_advanced)
    end
  end

  describe "Fort Yates 2024-25 published values" do
    @y "2024-2025"
    @f %{year: "2024-2025", type: "Comp", subgroup: "All"}

    defp area(dataset, low, high) do
      %{engagement("Disengaged", {:range, low, high}) | dataset: dataset, academic_year: @y}
    end

    defp fy_rows do
      [
        growth({:exact, "38"}, %{academic_year: @y}),
        growth({:exact, "41"}, %{academic_year: @y, subject: "Math"}),
        area(:engagement_behavioral, "0.15", "0.19"),
        area(:engagement_cognitive, "0.10", "0.14"),
        area(:engagement_emotional, "0.40", "0.44"),
        # ELA All Grades: Novice 40%–49%, Proficient 20%–29%; Math: Novice
        # 70%–79%, Proficient 0%–10% (the published 2024-25 ranges).
        perf("Novice", {:range, "0.4", "0.49"}, %{academic_year: @y}),
        perf("Proficient", {:range, "0.2", "0.29"}, %{academic_year: @y}),
        perf("Novice", {:range, "0.7", "0.79"}, %{academic_year: @y, subject: "Math"}),
        perf("Proficient", {:range, "0", "0.1"}, %{academic_year: @y, subject: "Math"})
      ]
    end

    defp fy(reference) do
      g = ResultGoals.for_filters(fy_rows(), Map.put(@f, :reference, reference), plan())

      %{
        ela_growth: g.growth[{"ELA", "All Grades"}]["OverallGrowthPercentile"],
        math_growth: g.growth[{"Math", "All Grades"}]["OverallGrowthPercentile"],
        behavioral: g.engagement[:engagement_behavioral]["Disengaged"],
        cognitive: g.engagement[:engagement_cognitive]["Disengaged"],
        emotional: g.engagement[:engagement_emotional]["Disengaged"],
        ela_novice: g.achievement[{"Reading", "All Grades"}]["Novice"],
        ela_proficient: g.achievement[{"Reading", "All Grades"}]["Proficient"],
        math_novice: g.achievement[{"Math", "All Grades"}]["Novice"],
        math_proficient: g.achievement[{"Math", "All Grades"}]["Proficient"]
      }
    end

    test "against the 18-month targets" do
      r = fy(:review_18m)
      # Growth 38 vs 43 and 41 vs 46; Disengaged 15–19% vs 12%, 10–14% vs 7%,
      # 40–44% vs 32.9%: all red.
      for k <- ~w(ela_growth math_growth behavioral cognitive emotional)a do
        assert r[k].status == :misses, "#{k}"
      end

      assert ResultGoals.short_label(r.behavioral) == "Above target"
      assert ResultGoals.short_label(r.ela_growth) == "Below target"
      # ELA Novice 40–49% vs 39%: above (red). ELA Proficient 20–29% vs 27%:
      # overlaps (amber). Math Novice 70–79% vs 72%: overlaps. Math
      # Proficient 0–10% vs 8%: overlaps.
      assert r.ela_novice.status == :misses
      assert r.ela_proficient.status == :overlaps
      assert r.math_novice.status == :overlaps
      assert r.math_proficient.status == :overlaps
      assert Enum.all?(Map.values(r), &(&1.timing == :before_plan))
    end

    test "against the 36-month targets" do
      r = fy(:review_36m)
      # Growth 38 vs 51, 41 vs 52; Disengaged vs 8%, 5%, 22.9%: red.
      for k <- ~w(ela_growth math_growth behavioral cognitive emotional)a do
        assert r[k].status == :misses, "#{k}"
      end

      # ELA Novice 40–49% vs 31%: red. ELA Proficient 20–29% vs 32%: red.
      # Math Novice 70–79% vs 68%: red. Math Proficient 0–10% vs 12%: red.
      for k <- ~w(ela_novice ela_proficient math_novice math_proficient)a do
        assert r[k].status == :misses, "#{k}"
      end

      assert ResultGoals.goal_line(r.ela_growth) ==
               "2024-2025 result · Growth percentile target: 51 · 36-month · G2-M3"
    end

    test "section notes state the assumption and the future targets once" do
      g = ResultGoals.for_filters(fy_rows(), @f, plan())

      assert ResultGoals.section_notes(:achievement, g.achievement) == [
               "Reference comparison; Combined assessment assumed for workbook targets.",
               "2024-2025 results predate the plan, so they are compared against future targets."
             ]

      grade = [perf("Novice", {:range, "0.4", "0.49"}, %{academic_year: @y, grade: "7"})]
      g = ResultGoals.for_filters(fy_rows() ++ grade, @f, plan())

      assert List.last(ResultGoals.section_notes(:achievement, g.achievement)) ==
               "Grade-level colors compare each grade’s results with the schoolwide target for reference. These are not separate grade-level goals."

      assert hd(ResultGoals.section_notes(:engagement, g.engagement)) ==
               "Reference comparison; schoolwide survey population match assumed."

      assert ResultGoals.section_notes(:growth, %{}) == []
    end
  end

  describe "annual/2 (Annual Targets table and state tables)" do
    defp goal(year, subject, target),
      do: %{
        school_year: year,
        subject: subject,
        target_value: Decimal.new(target),
        measure: :proficient_or_advanced,
        includes_alternate: true
      }

    test "uses the bound rule on its own year's result, never another year's" do
      ranged = [
        perf("Proficient", {:range, "0.2", "0.29"}),
        perf("Advanced", {:range, "0", "0.1"})
      ]

      assert %{status: :overlaps, value: "20%–39%"} =
               ResultGoals.annual(goal(@year, :ela, "0.25"), ranged)

      assert ResultGoals.annual(goal(@year, :ela, "0.20"), ranged).status == :meets
      assert ResultGoals.annual(goal(@year, :ela, "0.40"), ranged).status == :misses
      assert ResultGoals.annual(goal("2026-2027", :ela, "0.25"), ranged).status == :not_published
    end

    test "matches the state-table cell for the same year" do
      rows = [perf("Proficient", {:range, "0.2", "0.29"}), perf("Advanced", {:range, "0", "0.1"})]
      cell = ela(rows, :proficient_or_advanced)
      table = ResultGoals.annual(hd(FortYates.annual_assessment_goals()), rows)

      assert Map.take(cell, [:status, :value, :target]) ==
               Map.take(table, [:status, :value, :target])
    end
  end

  describe "grade-level reference colors (Achievement, grades 6–8)" do
    defp grade(measure, v, g, overrides \\ %{}),
      do: perf(measure, v, Map.merge(%{grade: g}, overrides))

    defp at(rows, subject, g, measure, opts \\ [], filters \\ @filters),
      do: match(rows, :achievement, {subject, g}, measure, opts, filters)

    test "compare each grade with the schoolwide target, labeled as a reference" do
      # G2-M2 ELA Novice 18-month 39% (lower is better).
      novice = &at([grade("Novice", &1, "7")], "Reading", "7", "Novice")

      assert %{kind: :grade_reference, status: :meets} = m = novice.({:range, "0.3", "0.39"})
      assert ResultGoals.short_label(m) == "At or below schoolwide target"
      assert ResultGoals.goal_line(m) == "Schoolwide reference: 39% · 18-month"
      assert ResultGoals.explanation(m) =~ "not a separate grade-level goal"

      assert ResultGoals.short_label(novice.({:range, "0.40", "0.49"})) ==
               "Above schoolwide target"

      assert ResultGoals.short_label(novice.({:range, "0.35", "0.45"})) ==
               "Range overlaps schoolwide target"

      assert novice.({:exact, "0.39"}).status == :meets, "equality meets"

      # G3-M1 Math Proficient 18-month 8% (higher is better).
      prof = &at([grade("Proficient", &1, "6", %{subject: "Math"})], "Math", "6", "Proficient")

      assert ResultGoals.short_label(prof.({:range, "0.08", "0.2"})) ==
               "At or above schoolwide target"

      assert ResultGoals.short_label(prof.({:range, "0", "0.07"})) == "Below schoolwide target"
      assert prof.({:range, "0", "0.2"}).status == :overlaps
      assert prof.({:range, "0", "0.08"}).status == :overlaps
      assert prof.({:exact, "0.08"}).status == :meets
    end

    test "the selected checkpoint decides the schoolwide target" do
      rows = [grade("Proficient", {:range, "0.2", "0.29"}, "8")]
      m18 = at(rows, "Reading", "8", "Proficient")
      m36 = at(rows, "Reading", "8", "Proficient", [], Map.put(@filters, :reference, :review_36m))

      # G2-M1: 27% (18-month) overlaps; 32% (36-month) is above the range.
      assert m18.status == :overlaps
      assert m36.status == :misses
      assert ResultGoals.goal_line(m36) == "Schoolwide reference: 32% · 36-month"
    end

    test "missing and suppressed grade values are gray" do
      assert %{status: :gray} = at([grade("Novice", :suppressed, "7")], "Reading", "7", "Novice")

      by = ResultGoals.for_filters([grade("Partially", {:exact, "0.3"}, "7")], @filters, plan())

      assert %{status: :gray, reasons: [:not_published]} =
               by.achievement[{"Reading", "7"}]["Novice"]
    end

    test "only Novice and Proficient, ELA and Math, grades 6–8, Combined, all students" do
      rows = [
        grade("Novice", {:exact, "0.5"}, "7"),
        grade("Partially", {:exact, "0.3"}, "7"),
        grade("Proficient", {:exact, "0.1"}, "7"),
        grade("Advanced", {:exact, "0.1"}, "7")
      ]

      by = ResultGoals.for_filters(rows, @filters, plan()).achievement[{"Reading", "7"}]
      assert Map.keys(by) |> Enum.sort() == ["Novice", "Proficient"]

      science = [grade("Novice", {:exact, "0.5"}, "8", %{subject: "Science"})]
      assert at(science, "Science", "8", "Novice") == nil

      assert at([grade("Novice", {:exact, "0.5"}, "5")], "Reading", "5", "Novice") == nil

      for type <- ~w(Reg Alt) do
        typed = [grade("Novice", {:exact, "0.5"}, "7", %{assessment_type: type})]
        assert at(typed, "Reading", "7", "Novice", [], %{@filters | type: type}) == nil
      end

      female = [grade("Novice", {:exact, "0.5"}, "7", %{subgroup: "Female"})]
      assert at(female, "Reading", "7", "Novice", [], %{@filters | subgroup: "Female"}) == nil

      # Without the Combined assumption there are no grade references.
      assert at(rows, "Reading", "7", "Novice", assumptions: %{}) == nil

      # Other schools get none.
      other = %{FortYates.school() | state_entity_id: "0000000000"}

      assert match(rows, :achievement, {"Reading", "7"}, "Novice", [], @filters, plan(other)) ==
               nil
    end

    test "All Grades comparisons are unchanged by grade rows" do
      all = [perf("Novice", {:range, "0.4", "0.49"})]
      alone = ela(all, "Novice")
      with_grades = ela(all ++ [grade("Novice", {:exact, "0.1"}, "6")], "Novice")

      assert alone == with_grades
      assert %{kind: :workbook, status: :misses} = alone
      assert ResultGoals.short_label(alone) == "Above target"
    end
  end

  describe "range boundaries (one shared rule)" do
    defp d(v), do: Decimal.new(v)
    defp rng(l, h), do: {d(l), d(h)}

    test "the target-20 examples, in both directions" do
      t = d("20")
      # Higher is better: 20–30 meets; 10–20 overlaps.
      assert ResultGoals.classify(:higher_is_better, rng("20", "30"), t) == :meets
      assert ResultGoals.classify(:higher_is_better, rng("10", "20"), t) == :overlaps
      assert ResultGoals.classify(:higher_is_better, rng("10", "19.9"), t) == :misses
      # Lower is better: 10–20 meets; 20–30 overlaps.
      assert ResultGoals.classify(:lower_is_better, rng("10", "20"), t) == :meets
      assert ResultGoals.classify(:lower_is_better, rng("20", "30"), t) == :overlaps
      assert ResultGoals.classify(:lower_is_better, rng("20.1", "30"), t) == :misses
      # Exact 20 meets in both directions.
      assert ResultGoals.classify(:higher_is_better, rng("20", "20"), t) == :meets
      assert ResultGoals.classify(:lower_is_better, rng("20", "20"), t) == :meets
    end

    test "every section applies it the same way" do
      # Lower is better, Achievement (G2-M2 ELA Novice, 18-month 39%).
      novice = &ela([perf("Novice", {:range, &1, &2})], "Novice").status
      assert novice.("0.29", "0.39") == :meets
      assert novice.("0.39", "0.49") == :overlaps

      # Lower is better, Engagement (G4-M2 Emotional Disengaged, 32.9%).
      emo = fn l, h ->
        rows = [engagement("Disengaged", {:range, l, h})]

        ResultGoals.for_filters(rows, @filters, plan()).engagement[:engagement_emotional][
          "Disengaged"
        ].status
      end

      assert emo.("0.229", "0.329") == :meets
      assert emo.("0.329", "0.429") == :overlaps

      # Higher is better, Growth (G2-M3 18-month 43).
      assert gp({:range, "43", "50"}).status == :meets
      assert gp({:range, "36", "43"}).status == :overlaps

      # Higher is better, annual targets (ELA 2025-26 25%).
      annual = fn p_lo, p_hi ->
        rows = [perf("Proficient", {:range, p_lo, p_hi}), perf("Advanced", {:exact, "0"})]
        ResultGoals.annual(hd(FortYates.annual_assessment_goals()), rows).status
      end

      assert annual.("0.25", "0.35") == :meets
      assert annual.("0.15", "0.25") == :overlaps
    end
  end

  describe "grade-level Growth reference colors (grades 6–8)" do
    defp gg(v, subject, g, overrides \\ %{}),
      do: growth(v, Map.merge(%{subject: subject, grade: g}, overrides))

    defp gat(rows, subject, g, filters \\ @filters),
      do: match(rows, :growth, {subject, g}, "OverallGrowthPercentile", [], filters)

    test "compare each grade's percentile with the schoolwide target, in percentiles" do
      # G2-M3 ELA 18-month 43; G3-M3 Math 18-month 46.
      m = gat([gg({:exact, "35"}, "ELA", "7")], "ELA", "7")
      assert %{kind: :grade_reference, status: :misses} = m
      assert ResultGoals.short_label(m) == "Below schoolwide target"

      assert ResultGoals.goal_line(m) ==
               "Growth percentile target: 43 · 18-month · Schoolwide reference"

      refute ResultGoals.goal_line(m) =~ "%"

      high = gat([gg({:exact, "64"}, "ELA", "8")], "ELA", "8")
      assert ResultGoals.short_label(high) == "At or above schoolwide target"
      assert gat([gg({:exact, "43"}, "ELA", "6")], "ELA", "6").status == :meets
      assert gat([gg({:range, "44", "50"}, "Math", "7")], "Math", "7").status == :overlaps

      assert ResultGoals.short_label(gat([gg({:range, "44", "50"}, "Math", "7")], "Math", "7")) ==
               "Range overlaps schoolwide target"

      m36 =
        gat(
          [gg({:exact, "50"}, "ELA", "8")],
          "ELA",
          "8",
          Map.put(@filters, :reference, :review_36m)
        )

      assert m36.status == :misses

      assert ResultGoals.goal_line(m36) ==
               "Growth percentile target: 51 · 36-month · Schoolwide reference"

      math36 =
        gat(
          [gg({:exact, "52"}, "Math", "7")],
          "Math",
          "7",
          Map.put(@filters, :reference, :review_36m)
        )

      assert math36.status == :meets
    end

    test "only the overall growth percentile, grades 6–8, all students; any assessment type" do
      rows = [
        gg({:exact, "60"}, "ELA", "7"),
        %{gg({:range, "0", "0.2"}, "ELA", "7") | measure: "DoesNotMeet", unit: :proportion},
        %{gg({:range, "0.4", "0.49"}, "ELA", "7") | measure: "Meets", unit: :proportion}
      ]

      by = ResultGoals.for_filters(rows, @filters, plan()).growth[{"ELA", "7"}]
      assert Map.keys(by) == ["OverallGrowthPercentile"]

      # Growth has no assessment-type breakdown: the Standard view keeps it.
      assert gat(rows, "ELA", "7", %{@filters | type: "Reg"}).status == :meets

      assert gat([gg({:exact, "60"}, "ELA", "5")], "ELA", "5") == nil
      female = [gg({:exact, "60"}, "ELA", "7", %{subgroup: "Female"})]
      assert gat(female, "ELA", "7", %{@filters | subgroup: "Female"}) == nil

      other = %{FortYates.school() | state_entity_id: "0000000000"}

      assert match(
               rows,
               :growth,
               {"ELA", "7"},
               "OverallGrowthPercentile",
               [],
               @filters,
               plan(other)
             ) == nil
    end

    test "suppressed values stay neutral; All Grades is unchanged; the note is growth-specific" do
      assert %{status: :gray} = gat([gg(:suppressed, "ELA", "7")], "ELA", "7")

      all = [growth({:exact, "38"})]
      with_grades = all ++ [gg({:exact, "64"}, "ELA", "8")]

      assert gp({:exact, "38"}) ==
               match(with_grades, :growth, {"ELA", "All Grades"}, "OverallGrowthPercentile")

      goals = ResultGoals.for_filters(with_grades, @filters, plan())

      assert List.last(ResultGoals.section_notes(:growth, goals.growth)) ==
               "Grade-level colors compare each grade’s growth percentile with the schoolwide target for reference. These are not separate grade-level goals."
    end
  end

  describe "methodology wording" do
    test "explains schoolwide matching and grade-level references with the same targets" do
      text = Enum.join(ResultGoals.methodology(), " ")

      assert text =~
               "Schoolwide results (All Grades, all students) are matched to the schoolwide goals."

      assert text =~
               "are compared with those same schoolwide targets for reference; these are not separate grade-level goals."

      refute text =~ "never a single grade"
    end
  end
end
