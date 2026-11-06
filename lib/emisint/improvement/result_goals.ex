defmodule Emisint.Improvement.ResultGoals do
  @moduledoc """
  Compares a school's published ND Insights results with its own goals, for
  the main Achievement, Growth and Engagement tables on the dashboard and in
  the PDF. North Dakota comparisons are separate (`NdInsights.StateComparison`)
  and never affect a status here.

  This is a **dashboard comparison rule**, not an official ND FIRST scoring
  method. Nothing here records a review result, sets a rating or feeds the
  payment estimate: those come only from explicit review entries
  (`GoalStatus`, `FromNdInsights`, `Payment`).

  **Which goal a published value matches.** Only an explicit correspondence
  is used; nothing is inferred from similar wording. Each school's own
  definition module declares it (`comparison/0`, found by InstitutionID
  through `Seeds.module_for/1`; see `config/1`), so one school's metric
  codes, grade rules or assumptions never apply to another:

    * Fort Yates (`Seeds.FortYates`): Proficient alone → G2-M1 / G3-M1;
      Novice → G2-M2 / G3-M2; Overall growth percentile → G2-M3 / G3-M3;
      Disengaged by domain → G4-M2 / G4-M3 / G4-M4.
    * Oberon (`Seeds.Oberon`): Proficient or Advanced (derived) → G1-M1 /
      G2-M1; Novice → G1-M2 / G2-M2; Emotional Committed, Compliant and
      Disengaged → G4-M1 / G4-M2 / G4-M3.
    * Proficient or Advanced (derived) → also the annual state-assessment
      target for the same school year (`AnnualAssessmentGoal`); never another
      year's. Where both exist, the annual comparison is shown.

  A school without a definition module gets no workbook match. Every goal is
  schoolwide: the All Grades row for all students is matched to it. A school
  may also compare eligible grade-level rows with the same schoolwide target
  for reference (`grade_reference`; Fort Yates: grades 6–8, all students);
  these are not separate grade-level goals. Student groups are never matched.

  **Reference checkpoint.** A workbook value is compared with the selected
  checkpoint's target (`:reference`, `:review_18m` or `:review_36m`). Which
  assessment year counts for each review isn't established (PLAN item 27),
  so the comparison is labeled as a reference: "against future target" for
  a result from before the plan began (the school's `plan_start_year`),
  otherwise "review year unconfirmed". With an established review year
  (`:established` option) a result from that year is a same-year comparison.

  **Demo assumptions** (each school's `assumptions`; `demo_assumptions/0`
  is Fort Yates's, configurable, not verified facts): the workbook's
  achievement targets apply to the Combined assessment, all students, All
  Grades, so Standard and Alternate views get no workbook verdict; its
  engagement targets apply to the school's schoolwide survey population.
  Without an assumption (`assumptions: %{}`) the affected comparisons are
  gray. Missing or suppressed values and unconfirmed targets are gray too.

  **Rule** (published bounds; an exact value has equal bounds; equality
  meets; no midpoints or tolerances):

    * higher is better: lower bound ≥ target meets; upper bound < target
      misses; otherwise the range overlaps the target.
    * lower is better: upper bound ≤ target meets; lower bound > target
      misses; otherwise the range overlaps the target.

  Each match: `%{kind, code, name, direction, year, value, target, status,
  reasons, timing, tone}` with `status` `:meets | :misses | :overlaps | :gray`.
  """

  alias Emisint.Improvement.{Display, Percent, Seeds}
  alias Emisint.Improvement.Seeds.FortYates
  alias Emisint.NdInsights.SchoolResults

  @established %{review_years: %{}, assessment_type: nil}

  # A school without a definition module: no workbook matches, no assumptions.
  @no_comparison %{
    plan_start_year: nil,
    workbook: [],
    assumptions: %{},
    grade_reference: nil,
    matching: nil,
    assumptions_text: nil,
    assumptions_short: nil,
    section_notes: %{},
    annual_note: nil,
    report_notes: []
  }

  @not_official "A dashboard comparison rule, not an official ND FIRST scoring method; it doesn't record a review result, set a rating or affect the payment estimate."

  @grade_note "Grade-level colors compare each grade’s results with the schoolwide target for reference. These are not separate grade-level goals."
  @growth_grade_note "Grade-level colors compare each grade’s growth percentile with the schoolwide target for reference. These are not separate grade-level goals."

  @checkpoints %{
    review_18m: {:target_18m, "18-month target"},
    review_36m: {:target_36m, "36-month target"}
  }

  @doc "What is established for workbook targets (nothing yet)."
  def established, do: @established

  @doc """
  The demo assumptions applied to Fort Yates workbook reference comparisons:
  `assessment_type` (the workbook achievement targets count this assessment)
  and `engagement_population` (`:schoolwide`: the engagement targets count
  the school's own survey population). Configurable, not verified.
  """
  def demo_assumptions, do: FortYates.comparison().assumptions

  @doc """
  A school's comparison configuration (its definition module's
  `comparison/0`, found by InstitutionID), or an empty one: no workbook
  matches, no assumptions and no notes.
  """
  def config(%{state_entity_id: id}) do
    case Seeds.module_for(id) do
      nil ->
        @no_comparison

      module ->
        if function_exported?(module, :comparison, 0),
          do: Map.merge(@no_comparison, module.comparison()),
          else: @no_comparison
    end
  end

  def config(_school), do: @no_comparison

  @doc "The selectable reference checkpoints, as `[{param, checkpoint, label}]`."
  def references,
    do: [{"18m", :review_18m, "18-month target"}, {"36m", :review_36m, "36-month target"}]

  @doc "The reference checkpoint for a request parameter (default the 18-month target)."
  def reference("36m"), do: :review_36m
  def reference(_param), do: :review_18m

  @doc "The request parameter for a reference checkpoint."
  def reference_param(:review_36m), do: "36m"
  def reference_param(_), do: "18m"

  @doc "The label of a reference checkpoint, e.g. \"18-month target\"."
  def reference_label(checkpoint), do: @checkpoints |> Map.fetch!(checkpoint) |> elem(1)

  @doc """
  Goal comparisons for the published values shown for `filters`
  (`%{year, type, subgroup}`, optionally `reference`), keyed like the
  dashboard tables:

    * `achievement` — `%{{subject, grade} => %{measure | :proficient_or_advanced => match}}`
    * `growth` — `%{{subject, grade} => %{measure => match}}`
    * `engagement` — `%{area => %{engagement_level => match}}`

  `plan` is `%{school, metrics, annual_goals}`. Option `:established`
  (default `established/0`) gives `review_years` and the workbook
  `assessment_type`; option `:assumptions` replaces the school's own.
  """
  def for_filters(rows, %{year: year, type: type, subgroup: subgroup} = f, plan, opts \\ []) do
    config = config(plan.school)
    established = Map.merge(@established, Map.new(Keyword.get(opts, :established, %{})))
    assumptions = Map.new(Keyword.get(opts, :assumptions, config.assumptions))

    ctx = %{
      year: year,
      type: type,
      subgroup: subgroup,
      reference: Map.get(f, :reference) || :review_18m,
      established: established,
      assessment_type: established.assessment_type || assumptions[:assessment_type],
      assumed_type?: established.assessment_type == nil and assumptions[:assessment_type] != nil,
      population: assumptions[:engagement_population],
      plan_start_year: config.plan_start_year,
      grade_reference: config.grade_reference
    }

    workbook = workbook(plan, config)

    %{
      achievement:
        Map.new(SchoolResults.performance(rows, year, type, subgroup), fn row ->
          {{row.subject, row.grade},
           Map.merge(
             workbook_matches(workbook, :achievement, row, row.subject, ctx),
             annual_matches(plan.annual_goals, row, ctx, rows)
           )}
        end),
      growth:
        Map.new(SchoolResults.growth(rows, year, subgroup), fn row ->
          {{row.subject, row.grade}, workbook_matches(workbook, :growth, row, row.subject, ctx)}
        end),
      engagement:
        Map.new(SchoolResults.engagement(rows, year), fn row ->
          {row.area,
           workbook_matches(
             workbook,
             :engagement,
             Map.put(row, :grade, "All Grades"),
             row.area,
             %{ctx | subgroup: "All"}
           )}
        end)
    }
  end

  # The plan's metrics that have an explicit published counterpart in the
  # school's own configuration. A metric is used only when it is still the
  # expected one: its stored `performance_measure` (an atom) or its exact
  # workbook wording (a string).
  defp workbook(%{metrics: metrics}, config) do
    by_code = Map.new(metrics, &{&1.code, &1})

    for {code, expected, section, key, published, label} <- config.workbook,
        metric = by_code[code],
        metric != nil and expected?(metric, expected),
        do: %{metric: metric, section: section, key: key, measure: published, label: label}
  end

  defp expected?(metric, measure) when is_atom(measure), do: metric.performance_measure == measure
  defp expected?(metric, wording) when is_binary(wording), do: metric.description == wording

  defp workbook_matches(workbook, section, row, key, ctx) do
    cond do
      schoolwide?(row, ctx) and type_matches?(section, ctx) ->
        for w <- workbook, w.section == section, w.key == key, into: %{} do
          {w.measure, workbook_match(w, published(row, w.measure), section, ctx)}
        end

      grade_reference?(section, row, ctx) ->
        for w <- workbook,
            w.section == section,
            w.key == key,
            w.measure in Map.get(ctx.grade_reference, section, []),
            into: %{} do
          match = workbook_match(w, published(row, w.measure), section, ctx)
          {w.measure, Map.merge(match, %{kind: :grade_reference, grade: row.grade})}
        end

      true ->
        %{}
    end
  end

  # The published value for a workbook measure: a level row, or the derived
  # Proficient-or-Advanced interval (as published bounds, never a midpoint).
  defp published(row, :proficient_or_advanced) do
    case Map.get(row, :proficient_or_advanced) do
      {:ok, low, high} when low == high -> %{value_state: :exact, value: low}
      {:ok, low, high} -> %{value_state: :range, range_low: low, range_high: high}
      {:not_derivable, _reason} -> :not_derivable
      _ -> nil
    end
  end

  defp published(row, measure), do: row.levels[measure]

  # Grade rows in the school's `grade_reference` grades, all students, are
  # compared with the schoolwide workbook target for reference only; they
  # are not grade-level goals. Achievement: ELA and Math, under the school's
  # assessment-type assumption. Growth: the growth download has no
  # assessment type, so none is required. Subgroups, other measures and
  # schools without `grade_reference` get none.
  defp grade_reference?(_section, _row, %{grade_reference: nil}), do: false

  defp grade_reference?(:achievement, row, ctx),
    do:
      row.grade in ctx.grade_reference.grades and row.subject in ["Reading", "Math"] and
        ctx.subgroup == "All" and ctx.assessment_type != nil and ctx.type == ctx.assessment_type

  defp grade_reference?(:growth, row, ctx),
    do:
      row.grade in ctx.grade_reference.grades and row.subject in ["ELA", "Math"] and
        ctx.subgroup == "All"

  defp grade_reference?(_section, _row, _ctx), do: false

  defp schoolwide?(row, ctx), do: row.grade == "All Grades" and ctx.subgroup == "All"

  # An established workbook assessment type matches only rows of that type.
  defp type_matches?(:achievement, %{type: type, assessment_type: t}), do: t in [nil, type]

  defp type_matches?(_section, _ctx), do: true

  defp workbook_match(w, value, section, ctx) do
    {field, label} = Map.fetch!(@checkpoints, ctx.reference)
    target = Display.target(w.metric, field)

    blocked =
      cond do
        range_target?(w.metric, field) ->
          :target_is_range

        not match?({:number, _}, target) ->
          :target_not_comparable

        section == :engagement and ctx.population == nil ->
          :population_unverified

        section == :achievement and ctx.assessment_type == nil ->
          :assessment_type_unconfirmed

        true ->
          nil
      end

    %{
      kind: :workbook,
      code: w.metric.code,
      percentile?: w.metric.unit == :percentile,
      name: "#{w.metric.code} #{w.label}",
      direction: w.metric.direction,
      year: ctx.year,
      value: value_text(value, w.metric),
      target: %{label: label, text: elem(target, 1)},
      timing: timing(ctx.established.review_years[ctx.reference], ctx.year, ctx.plan_start_year),
      assumed: assumed(section, ctx)
    }
    |> judge(blocked, interval(value), Map.get(w.metric, field))
  end

  # A target written as a range (e.g. "55-60%"): the workbook doesn't say
  # when a range target is met, so no verdict is given.
  defp range_target?(metric, field) do
    case Display.target(metric, field) do
      {:text, raw} -> Regex.match?(~r/^\s*\d+(\.\d+)?\s*%?\s*[-–]\s*\d+(\.\d+)?\s*%?\s*$/, raw)
      _ -> false
    end
  end

  defp assumed(:achievement, %{assumed_type?: true}), do: [:combined_assessment]
  defp assumed(:engagement, %{population: :schoolwide}), do: [:schoolwide_survey]
  defp assumed(_section, _ctx), do: []

  # :before_plan — a result from before the plan began, compared with a
  # target that was still in the future; :unconfirmed — the review's
  # assessment year isn't established.
  defp timing(nil, year, start) do
    if start != nil and year < start, do: :before_plan, else: :unconfirmed
  end

  defp timing(year, year, _start), do: :same_year

  defp timing(review_year, year, _start) when year < review_year,
    do: {:before_review, review_year}

  defp timing(review_year, _year, _start), do: {:after_review, review_year}

  defp judge(match, blocked, _interval, _target) when blocked != nil, do: gray(match, blocked)
  defp judge(match, _blocked, {:missing, reason}, _target), do: gray(match, reason)

  defp judge(match, nil, interval, target) do
    status = classify(match.direction, interval, target)
    Map.merge(match, %{status: status, reasons: [], tone: tone(status)})
  end

  @doc """
  The dashboard rule for published bounds `{low, high}` (an exact value has
  equal bounds) against `target`: `:meets`, `:misses` or `:overlaps`.

    * higher is better: `low >= target` meets; `high < target` misses.
    * lower is better: `high <= target` meets; `low > target` misses.

  Otherwise the range overlaps. A range touching the target on its
  favorable side meets (lower is better: 10–20 vs 20); one touching it on
  its unfavorable side overlaps (higher is better: 10–20 vs 20).
  """
  def classify(:lower_is_better, {low, high}, target) do
    cond do
      Decimal.compare(high, target) != :gt -> :meets
      Decimal.compare(low, target) == :gt -> :misses
      true -> :overlaps
    end
  end

  def classify(_higher_is_better, {low, high}, target) do
    cond do
      Decimal.compare(low, target) != :lt -> :meets
      Decimal.compare(high, target) == :lt -> :misses
      true -> :overlaps
    end
  end

  defp gray(match, reason),
    do: Map.merge(match, %{status: :gray, reasons: [reason], tone: :muted})

  # Published bounds: an exact value has equal bounds.
  defp interval(%{value_state: :exact, value: v}), do: {v, v}
  defp interval(%{value_state: :range, range_low: l, range_high: h}), do: {l, h}
  defp interval(%{value_state: :suppressed}), do: {:missing, :suppressed}
  defp interval(:not_derivable), do: {:missing, :not_derivable}
  defp interval(_value), do: {:missing, :not_published}

  # Annual Proficient-or-Advanced targets: same school year, subject, all
  # grades, all students, and Combined (or Standard when the goal excludes
  # the alternate assessment). The derived value comes from
  # `SchoolResults.compare_goal/2`; another year's target is never used.
  defp annual_matches(goals, row, ctx, rows) do
    subject = %{"Reading" => :ela, "Math" => :math}[row.subject]

    for goal <- goals,
        goal.subject == subject and goal.school_year == ctx.year and
          goal.measure == :proficient_or_advanced,
        schoolwide?(row, ctx),
        ctx.type == if(goal.includes_alternate, do: "Comp", else: "Reg"),
        into: %{},
        do: {:proficient_or_advanced, annual(goal, rows)}
  end

  @doc """
  One annual Proficient-or-Advanced target compared with the published
  result of its own school year (derived by `SchoolResults.compare_goal/2`)
  under the dashboard rule. Used by the state tables and the Annual Targets
  table, so they always agree. `status` is `:not_published` when no matching
  result has been imported; `missing` then says "Not yet published" or "No
  result imported".
  """
  def annual(goal, rows) do
    comparison = SchoolResults.compare_goal(goal, rows)

    match = %{
      kind: :annual,
      code: nil,
      name: "#{if goal.subject == :ela, do: "ELA", else: "Math"} Proficient or Advanced",
      direction: :higher_is_better,
      year: goal.school_year,
      value: annual_value(comparison),
      target: %{
        label: "#{goal.school_year} annual target",
        text: Percent.format(goal.target_value)
      },
      timing: :same_year,
      assumed: []
    }

    case comparison do
      %{low: low, high: high} ->
        judge(match, nil, {low, high}, goal.target_value)

      %{status: :not_derivable} ->
        gray(match, :not_derivable)

      _ ->
        Map.merge(match, %{
          status: :not_published,
          reasons: [:not_published],
          tone: :muted,
          missing: missing_annual_text(goal.school_year, rows)
        })
    end
  end

  # An annual target with no matching result: "Not yet published" when no
  # achievement results from that year or later have been imported, otherwise
  # "No result imported" (an earlier year whose download isn't on file, e.g.
  # Oberon's 2018-19 target).
  defp missing_annual_text(year, rows) do
    later? =
      Enum.any?(rows, &(&1.dataset == :assessment_performance and &1.academic_year >= year))

    if later?, do: "No result imported", else: "Not yet published"
  end

  defp annual_value(%{low: low, high: high}) do
    if Decimal.equal?(low, high),
      do: Percent.format(low),
      else: "#{Percent.format(low)}–#{Percent.format(high)}"
  end

  defp annual_value(_comparison), do: nil

  defp value_text(%{value_state: :exact, value: v}, metric), do: Display.number(metric, v)

  defp value_text(%{value_state: :range, range_low: l, range_high: h}, metric),
    do: "#{Display.number(metric, l)}–#{Display.number(metric, h)}"

  defp value_text(_value, _metric), do: nil

  # ── Wording and tone (dashboard and PDF) ──────────────────────────────────

  @doc "`:success`, `:error`, `:warning` (range overlaps) or `:muted` (gray)."
  def tone(:meets), do: :success
  def tone(:misses), do: :error
  def tone(:overlaps), do: :warning
  def tone(_status), do: :muted

  @doc "The status shown under a value."
  def short_label(%{kind: :grade_reference, status: :meets, direction: :lower_is_better}),
    do: "At or below schoolwide target"

  def short_label(%{kind: :grade_reference, status: :meets}), do: "At or above schoolwide target"

  def short_label(%{kind: :grade_reference, status: :misses, direction: :lower_is_better}),
    do: "Above schoolwide target"

  def short_label(%{kind: :grade_reference, status: :misses}), do: "Below schoolwide target"

  def short_label(%{kind: :grade_reference, status: :overlaps}),
    do: "Range overlaps schoolwide target"

  def short_label(%{status: :meets}), do: "Meets target"
  def short_label(%{status: :misses, direction: :lower_is_better}), do: "Above target"
  def short_label(%{status: :misses}), do: "Below target"
  def short_label(%{status: :overlaps}), do: "Range overlaps target"
  def short_label(%{reasons: [reason | _]}), do: reason_label(reason)

  defp reason_label(:population_unverified), do: "Gray: survey population unverified"
  defp reason_label(:assessment_type_unconfirmed), do: "Gray: assessment type unconfirmed"
  defp reason_label(:target_not_comparable), do: "Gray: target needs confirmation"
  defp reason_label(:target_is_range), do: "Gray: target is a range"
  defp reason_label(:suppressed), do: "Gray: suppressed"
  defp reason_label(:not_derivable), do: "Gray: not derivable"
  defp reason_label(_missing), do: "Gray: not published"

  @doc "The timing caveat shown with a workbook comparison, or nil (none for gray)."
  def timing_label(%{status: :gray}), do: nil
  def timing_label(%{timing: :before_plan}), do: "Reference comparison against future target"
  def timing_label(%{timing: :unconfirmed}), do: "Reference comparison — review year unconfirmed"

  def timing_label(%{timing: {:before_review, _}}),
    do: "Reference comparison against future target"

  def timing_label(%{timing: {:after_review, y}}),
    do: "Reference comparison — the review counts #{y}"

  def timing_label(_match), do: nil

  @doc """
  The result year, target and checkpoint, compact enough for a table cell,
  e.g. "2024-2025 result vs 18-month target 43 · G2-M3 ELA growth percentile".
  """
  def goal_line(%{kind: :grade_reference, percentile?: true} = m),
    do: "Growth percentile target: #{m.target.text} · #{checkpoint(m)} · Schoolwide reference"

  def goal_line(%{kind: :grade_reference} = m),
    do: "Schoolwide reference: #{m.target.text} · #{checkpoint(m)}"

  def goal_line(%{percentile?: true} = m),
    do:
      "#{m.year} result · Growth percentile target: #{m.target.text} · #{checkpoint(m)} · #{m.code}"

  def goal_line(match) do
    direction = if match.direction == :lower_is_better, do: ", lower is better", else: ""

    "#{match.year} result vs #{match.target.label} #{match.target.text} · #{match.name}#{direction}"
  end

  defp checkpoint(m), do: String.replace(m.target.label, " target", "")

  @doc "Why the value has its color, with the caveats."
  def explanation(match) do
    [grade_text(match), verdict(match), timing_text(match), @not_official]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp grade_text(%{kind: :grade_reference, grade: grade, code: code}),
    do:
      "Grade #{grade} compared with the schoolwide #{code} target for reference; this is not a separate grade-level goal."

  defp grade_text(_match), do: nil

  defp verdict(%{status: :gray, reasons: [reason]} = m),
    do: "Not compared with the #{target_label(m)} (#{m.target.text}): " <> reason_text(reason)

  defp verdict(%{status: status} = m) do
    how =
      case {status, m.direction} do
        {:meets, :lower_is_better} -> "the whole published value is at or below"
        {:meets, _} -> "the whole published value is at or above"
        {:misses, :lower_is_better} -> "the whole published value is above"
        {:misses, _} -> "the whole published value is below"
        {:overlaps, _} -> "the published range includes values that meet and miss"
      end

    better = if m.direction == :lower_is_better, do: "lower", else: "higher"

    "#{m.year} published value #{m.value}: #{how} the #{target_label(m)} #{m.target.text} (#{better} is better; equal meets)."
  end

  defp target_label(%{percentile?: true} = m), do: "#{checkpoint(m)} growth percentile target"
  defp target_label(m), do: m.target.label

  defp timing_text(%{timing: :before_plan}),
    do:
      "This result is from before the plan began, so the target was still in the future: a reference comparison only."

  defp timing_text(%{timing: :unconfirmed}),
    do:
      "Which assessment year counts for this review hasn't been confirmed: a reference comparison only."

  defp timing_text(%{timing: {:before_review, y}}),
    do: "The review counts #{y} results; this earlier result is a reference comparison only."

  defp timing_text(%{timing: {:after_review, y}}),
    do: "The review counts #{y} results; this later result is a reference comparison only."

  defp timing_text(_match), do: nil

  defp reason_text(:population_unverified),
    do:
      "the workbook doesn't state the survey year or grades behind this metric, so the surveyed population isn't verified as the same."

  defp reason_text(:assessment_type_unconfirmed),
    do:
      "the workbook doesn't say whether this target counts the Combined, Standard or Alternate assessment."

  defp reason_text(:target_not_comparable), do: "the target isn't a confirmed number."

  defp reason_text(:target_is_range),
    do:
      "the target is written as a range, and the workbook doesn't define when a range target is met."

  defp reason_text(:not_derivable),
    do: "a component of Proficient or Advanced is suppressed or not published."

  defp reason_text(:suppressed), do: "the published value is suppressed."
  defp reason_text(:not_published), do: "no value is published."

  @doc """
  Why `year` has no annual goal: the school's goals start later (Fort
  Yates, 2025-26 on) or ended earlier (Oberon's historical goal period).
  Another year's target is never substituted.
  """
  def annual_years_note([], year),
    do:
      "This school has no annual Proficient-or-Advanced goals, so #{year} results have no annual goal."

  def annual_years_note(years, year) do
    {first, last} = Enum.min_max(years)

    if year > last,
      do:
        "The school's annual Proficient-or-Advanced goals end in #{last}, so #{year} results have no annual goal (another year's target is never substituted).",
      else:
        "The school's annual Proficient-or-Advanced goals start in #{first}, so #{year} results have no annual goal (another year's target is never substituted)."
  end

  @doc "The one-line legend kept visible with the result tables."
  def legend_short,
    do:
      "Colors compare each published value with this school's goals (a dashboard comparison rule, not an official ND FIRST scoring method). North Dakota comparisons are in the separate “North Dakota comparison” section."

  @doc """
  The short notes shown once above a section's table: what is assumed, and
  that historical results are compared against future targets. `section_goals`
  is that section's part of `for_filters/4`; empty when no workbook goal is
  shown.
  """
  def section_notes(section, section_goals) do
    all = for {_key, by} <- section_goals, {_m, match} <- by, do: match
    matches = Enum.filter(all, &(&1.kind == :workbook))

    grade_note =
      cond do
        not Enum.any?(all, &(&1.kind == :grade_reference)) -> []
        section == :growth -> [@growth_grade_note]
        true -> [@grade_note]
      end

    base_notes(section, matches) ++ grade_note
  end

  @doc "The note shown above Achievement when grade rows carry reference colors."
  def grade_note, do: @grade_note

  defp base_notes(section, matches) do
    case matches do
      [] ->
        []

      [first | _] ->
        [
          section_note(section, first),
          if(first.timing == :before_plan,
            do:
              "#{first.year} results predate the plan, so they are compared against future targets."
          )
        ]
        |> Enum.reject(&is_nil/1)
    end
  end

  defp section_note(:achievement, %{assumed: [:combined_assessment]}),
    do: "Reference comparison; Combined assessment assumed for workbook targets."

  defp section_note(:engagement, %{assumed: [:schoolwide_survey]}),
    do: "Reference comparison; schoolwide survey population match assumed."

  defp section_note(_section, _match), do: "Reference comparison against workbook targets."

  @doc "The reference note shown with the legend, for the selected checkpoint."
  def reference_note(checkpoint),
    do:
      "Workbook goals are compared with the #{reference_label(checkpoint)} as a reference: which assessment year counts for each review isn't confirmed. Reference comparisons don't record review results, set ratings or affect the payment estimate. Annual targets are compared only with results of their own year."

  @doc "The legend's colors, as `[{tone, label}]`."
  def legend_items,
    do: [
      success: "Meets target",
      error: "Below target (Above target when lower is better)",
      warning: "Range overlaps target",
      muted:
        "Gray: missing or suppressed, or the comparison isn't compatible (reason shown); no shading: no school goal for this measure"
    ]

  @doc """
  How results are compared with goals (methodology, dashboard and PDF), for a
  school's `config/1`. `methodology/0` is Fort Yates's.
  """
  def methodology, do: methodology(FortYates.comparison())

  def methodology(config) do
    [rule, reference, gray] = generic_methodology()

    [
      rule,
      config.matching && "Matching. " <> config.matching,
      reference,
      config.assumptions_text,
      gray
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp generic_methodology,
    do: [
      "Rule. A dashboard comparison rule, not an official ND FIRST scoring method. Published values are compared through their published low and high values (an exact value has equal bounds; ranges as published at insights.nd.gov/Data, never midpoints or tolerances). Higher is better: lower bound at or above the target meets, upper bound below it misses, otherwise the range overlaps the target. Lower is better: upper bound at or below the target meets, lower bound above it misses, otherwise it overlaps. Equal meets.",
      "Reference checkpoint. Workbook goals are compared with the selected 18- or 36-month target. Which assessment year counts for each review isn't confirmed, so these are reference comparisons: “against future target” for a result from before the plan began, otherwise “review year unconfirmed”. They never record a review result, set a rating or feed the payment estimate.",
      "Gray. Missing or suppressed values, missing or unconfirmed targets, and comparisons known to be incompatible are gray, with the reason."
    ]
end
