defmodule Emisint.NdInsights.StateComparison do
  @moduledoc """
  Compares a school's published ND Insights values with North Dakota
  benchmarks, and % tested with the 95% participation target. Shared by the
  school dashboard and the school PDF, so both show the same status, label,
  explanation and tone for every value.

  **Three kinds of comparison, never mixed** (`basis`):

    * `:state` — the matching "State of North Dakota" row
      (`Emisint.NdInsights.Benchmark`) for achievement and growth.
    * `:band` — the statewide middle-school (grades 6–8) Engagement Survey
      benchmark from the same year's technical brief
      (`Emisint.NdInsights.SurveyBenchmark`), only when that brief confirms
      the school's survey population.
    * `:target` — % tested against the 95% participation target.

  School goals are compared elsewhere (`Improvement.ResultGoals` for the
  main result tables, `Improvement.GoalStatus`, `SchoolResults.compare_goal/2`);
  nothing here is a goal status. The dashboard and PDF show these comparisons
  only in the separate North Dakota comparison section; % tested shows its
  95% participation target beside the value.

  **Statuses.** `:favorable` (green), `:unfavorable` (red), `:inconclusive`
  (yellow), `:matches` (equal exact values, neutral) and `:neutral` (gray:
  missing, suppressed, not rated or not comparable; `reason` says which).

  **Matching.** A state value is used only when the academic year, dataset,
  subject, grade, assessment type (where the dataset has one), student group,
  accommodations and measure all match. Nothing is substituted. "All Grades"
  aggregates are compared only when the school and the state publish the same
  grades for that subject; otherwise the statewide figure is context only.

  **Direction.** Lower Novice, Does not meet and Disengaged are favorable;
  higher Advanced, Proficient or Advanced, Exceeds, Meets or Exceeds, Overall
  growth percentile and Committed are favorable. Intermediate levels
  (Approaching Proficiency, Proficient alone, Approaches, Meets, Compliant)
  and the overall growth level are not rated.

  **Published bounds.** A comparison of published values: a published range
  is compared through its published low and high values (never a midpoint),
  an exact value as published. Insights says identifiable data is "converted
  to a range of values"; it does not document rounding or whether an endpoint
  such as 29% means "up to 29%" or "below 30%", so a verdict here is not a
  statement about the exact hidden value or an official determination.

    * The whole school interval strictly on the favorable side: favorable.
    * Strictly on the unfavorable side: unfavorable.
    * The intervals overlap or share an endpoint: inconclusive.
    * Equal exact values: matches the state.
  """

  alias Emisint.Improvement.Percent
  alias Emisint.NdInsights.{SchoolResults, SurveyBenchmark}

  @type status :: :favorable | :unfavorable | :inconclusive | :matches | :neutral
  @type t :: %{
          status: status(),
          basis: :state | :band | :target,
          reason: atom() | tuple(),
          measure_label: String.t(),
          school_text: String.t() | nil,
          state_text: String.t() | nil,
          detail: map()
        }

  @participation_target Decimal.new("0.95")
  @caveat " A comparison of published values (ranges as published, never midpoints; rounding isn't documented), not an exact or official determination."
  @target_source "20 U.S.C. 6311(c)(4)(E)(i): at least 95% of all students on the reading/language arts and mathematics assessments; also noted on Insights' participation charts"

  # ── Directions ────────────────────────────────────────────────────────────

  @doc "Which direction is favorable for a measure, or why it is not rated."
  def direction(:assessment_performance, "Novice"), do: :lower
  def direction(:assessment_performance, "Advanced"), do: :higher
  def direction(:assessment_performance, :proficient_or_advanced), do: :higher

  def direction(:assessment_performance, measure) when measure in ["Partially", "Proficient"],
    do: {:not_rated, :intermediate}

  def direction(:growth_rate, "DoesNotMeet"), do: :lower
  def direction(:growth_rate, "Exceeds"), do: :higher
  def direction(:growth_rate, :meets_or_exceeds), do: :higher
  def direction(:growth_rate, "OverallGrowthPercentile"), do: :higher

  def direction(:growth_rate, measure) when measure in ["Approaches", "Meets"],
    do: {:not_rated, :intermediate}

  def direction(:engagement, "Committed"), do: :higher
  def direction(:engagement, "Disengaged"), do: :lower
  def direction(:engagement, "Compliant"), do: {:not_rated, :intermediate}
  def direction(_dataset, _measure), do: {:not_rated, :no_interpretation}

  # ── Comparisons for the selected filters ─────────────────────────────────

  @doc """
  Comparisons for every published school value shown for `filters`
  (`%{year, type, subgroup}`), keyed like the dashboard tables:

    * `achievement` — `%{{subject, grade} => %{measure | :proficient_or_advanced | "PercentTested" => t}}`
      ("PercentTested" is compared with the 95% target)
    * `growth` — `%{{subject, grade} => %{measure | :meets_or_exceeds => t}}`
    * `engagement` — `%{area => %{engagement_level => t}}`
    * `survey_benchmark` — `SurveyBenchmark.compatibility/3` for the year
    * `survey_participation` — `t` or `nil`
  """
  def for_filters(school_rows, state_rows, %{year: year, type: type, subgroup: subgroup}) do
    school_perf = SchoolResults.performance(school_rows, year, type, subgroup)
    state_perf = SchoolResults.performance(state_rows, year, type, subgroup)
    school_growth = SchoolResults.growth(school_rows, year, subgroup)
    state_growth = SchoolResults.growth(state_rows, year, subgroup)
    school_survey = SchoolResults.engagement(school_rows, year)
    institution_id = Enum.find_value(school_rows, &Map.get(&1, :institution_id))

    survey =
      SurveyBenchmark.compatibility(
        institution_id,
        year,
        Map.new(school_survey, &{&1.area, &1.levels})
      )

    %{
      achievement: achievement(school_perf, state_perf, %{type: type, subgroup: subgroup}),
      growth: growth(school_growth, state_growth),
      engagement: engagement(school_survey, SchoolResults.engagement(state_rows, year), survey),
      survey_benchmark: survey,
      survey_participation: survey(SchoolResults.survey_participation(school_rows, year)),
      benchmark?: state_rows != []
    }
  end

  defp achievement(school, state, filters) do
    state_by = Map.new(state, &{{&1.subject, &1.grade}, &1})

    Map.new(school, fn row ->
      match = state_by[{row.subject, row.grade}]
      coverage = coverage(row, school, state)
      levels = (match && match.levels) || %{}

      comparisons =
        for {measure, label} <- SchoolResults.performance_levels(), into: %{} do
          {measure,
           compare(
             row.levels[measure],
             levels[measure],
             direction(:assessment_performance, measure),
             label: label,
             coverage: coverage
           )}
        end

      derived =
        compare_derived(
          row.levels,
          levels,
          {"Proficient", "Advanced"},
          direction(:assessment_performance, :proficient_or_advanced),
          label: "Proficient or Advanced",
          coverage: coverage
        )

      tested = participation(row.tested, row, filters)

      {{row.subject, row.grade},
       Map.merge(comparisons, %{:proficient_or_advanced => derived, "PercentTested" => tested})}
    end)
  end

  defp growth(school, state) do
    state_by = Map.new(state, &{{&1.subject, &1.grade}, &1})

    Map.new(school, fn row ->
      match = state_by[{row.subject, row.grade}]
      coverage = coverage(row, school, state)
      levels = (match && match.levels) || %{}

      measures =
        Enum.map(SchoolResults.growth_levels(), &elem(&1, 0)) ++
          ~w(OverallGrowthLevel OverallGrowthPercentile)

      comparisons =
        for measure <- measures, into: %{} do
          {measure,
           compare(row.levels[measure], levels[measure], direction(:growth_rate, measure),
             label: growth_label(measure),
             coverage: coverage
           )}
        end

      derived =
        compare_derived(
          row.levels,
          levels,
          {"Meets", "Exceeds"},
          direction(:growth_rate, :meets_or_exceeds),
          label: "Meets or Exceeds",
          coverage: coverage
        )

      {{row.subject, row.grade}, Map.put(comparisons, :meets_or_exceeds, derived)}
    end)
  end

  # Engagement is compared only with a confirmed middle-school benchmark of
  # the same year; the Insights state row (grades 3–12) is context only.
  defp engagement(school, state, survey) do
    state_by = Map.new(state, &{&1.area, &1})

    Map.new(school, fn row ->
      state_levels = (state_by[row.area] && state_by[row.area].levels) || %{}

      {row.area,
       for level <- ~w(Committed Compliant Disengaged), into: %{} do
         {level, survey_compare(row, level, state_levels[level], survey)}
       end}
    end)
  end

  defp survey_compare(row, level, state, {:ok, brief}) do
    case SurveyBenchmark.value(brief, row.area, level) do
      nil ->
        row.levels[level]
        |> compare(state, direction(:engagement, level), label: level, coverage: :same)
        |> context(:no_band_benchmark)

      band ->
        row.levels[level]
        |> compare(band, direction(:engagement, level), label: level, coverage: :same)
        |> Map.merge(%{basis: :band, state_text: band_text(band)})
        |> Map.update!(:detail, &Map.merge(&1, %{brief: brief, band: band}))
    end
  end

  defp survey_compare(row, level, state, survey) do
    row.levels[level]
    |> compare(state, direction(:engagement, level), label: level, coverage: :same)
    |> context({:survey, survey})
  end

  # Not compared: keep the state value as context and say why.
  defp context(%{reason: :school_unavailable} = c, _reason), do: c

  defp context(c, reason),
    do: %{c | status: :neutral} |> Map.put(:reason, reason) |> Map.put(:detail, %{})

  defp band_text(band),
    do:
      "#{Percent.format(band.value)} (ND grades 6–8: #{grouped(band.count)} of #{grouped(band.respondents)})"

  defp grouped(n),
    do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+$)/, ",")

  # Grade-level rows always match their own grade. "All Grades" matches only
  # when both sides publish the same grades for the subject.
  defp coverage(%{grade: "All Grades", subject: subject}, school, state) do
    school_grades = grades(school, subject)
    state_grades = grades(state, subject)

    if school_grades == state_grades and school_grades != [],
      do: :same,
      else: {:differs, school_grades, state_grades}
  end

  defp coverage(_row, _school, _state), do: :same

  defp grades(rows, subject) do
    rows
    |> Enum.filter(&(&1.subject == subject and &1.grade != "All Grades"))
    |> Enum.map(& &1.grade)
    |> Enum.uniq()
    |> Enum.sort_by(&grade_number/1)
  end

  defp grade_number(grade) do
    case Integer.parse(grade || "") do
      {n, _} -> n
      :error -> 99
    end
  end

  # ── Participation target ──────────────────────────────────────────────────

  # 20 U.S.C. 6311(c)(4)(E)(i) requires measuring at least 95% of all students
  # (and of each ESSA subgroup) on the reading/language arts and mathematics
  # assessments; Insights' participation charts note the same 95%. Compared
  # only where that is the published measure: ELA or math, Combined
  # assessment (standard and alternate), all students, the school's All Grades
  # row. Insights' student groups aren't verified as ESSA subgroups, so they
  # aren't compared.
  defp participation(tested, row, filters) do
    base = base("% tested", tested, nil, :target)

    cond do
      not published?(tested) -> Map.put(%{base | state_text: nil}, :reason, :school_unavailable)
      row.subject not in ["Reading", "Math"] -> Map.put(base, :reason, {:no_target, :subject})
      filters.type != "Comp" -> Map.put(base, :reason, {:no_target, :assessment_type})
      filters.subgroup != "All" -> Map.put(base, :reason, {:no_target, :subgroup})
      row.grade != "All Grades" -> Map.put(base, :reason, {:no_target, :grade})
      true -> judge_target(base, interval(operand(tested)))
    end
  end

  defp judge_target(base, {low, high}) do
    status =
      cond do
        Decimal.compare(low, @participation_target) != :lt -> :favorable
        Decimal.compare(high, @participation_target) == :lt -> :unfavorable
        true -> :inconclusive
      end

    %{base | status: status} |> Map.put(:reason, :target)
  end

  defp survey(nil), do: nil

  defp survey(%{status: :consistent, result: row}),
    do: Map.put(base("Survey participation", row, nil, :target), :reason, {:no_target, :survey})

  defp survey(%{status: :inconsistent}), do: nil

  # ── One comparison ────────────────────────────────────────────────────────

  @doc """
  Compares one published school value with the matching benchmark value.
  Options: `label` and `coverage` (`:same` or `{:differs, school_grades, state_grades}`).
  """
  def compare(school, state, direction, opts) do
    base = base(opts[:label], school, state, :state)

    cond do
      not published?(school) ->
        Map.put(%{base | state_text: nil}, :reason, :school_unavailable)

      state == nil ->
        Map.put(base, :reason, :benchmark_unavailable)

      not published?(state) ->
        Map.put(base, :reason, :benchmark_suppressed)

      true ->
        judge(base, operand(school), operand(state), direction, opts[:coverage])
    end
  end

  defp compare_derived(school_levels, state_levels, {a, b}, direction, opts) do
    school = derived(school_levels, a, b)
    state = derived(state_levels, a, b)

    base = %{
      status: :neutral,
      basis: :state,
      measure_label: opts[:label],
      school_text: derived_text(school),
      state_text: derived_text(state),
      detail: %{}
    }

    cond do
      school == :not_derivable -> Map.put(%{base | state_text: nil}, :reason, :school_unavailable)
      state_levels == %{} -> Map.put(base, :reason, :benchmark_unavailable)
      state == :not_derivable -> Map.put(base, :reason, :benchmark_suppressed)
      true -> judge(base, school, state, direction, opts[:coverage])
    end
  end

  defp base(label, school, state, basis) do
    %{
      status: :neutral,
      basis: basis,
      measure_label: label,
      school_text: value_text(school),
      state_text: value_text(state),
      detail: %{}
    }
  end

  defp judge(base, _school, _state, {:not_rated, reason}, _coverage),
    do: Map.put(base, :reason, reason)

  defp judge(base, _school, _state, _direction, {:differs, school_grades, state_grades}) do
    base
    |> Map.put(:reason, :grade_coverage)
    |> Map.put(:detail, %{school_grades: school_grades, state_grades: state_grades})
  end

  defp judge(base, {:exact, s}, {:exact, t}, direction, :same) do
    case Decimal.compare(s, t) do
      :eq -> %{base | status: :matches} |> Map.put(:reason, :equal)
      order -> verdict(base, if(order == :gt, do: :higher, else: :lower), direction, true)
    end
  end

  # A range on either side: compared through the published bounds.
  defp judge(base, school, state, direction, :same) do
    {s_lo, s_hi} = interval(school)
    {t_lo, t_hi} = interval(state)

    cond do
      Decimal.compare(s_lo, t_hi) == :gt ->
        verdict(base, :higher, direction, false)

      Decimal.compare(s_hi, t_lo) == :lt ->
        verdict(base, :lower, direction, false)

      # Not strictly apart: they overlap, or only share an endpoint.
      true ->
        overlap? = Decimal.compare(s_lo, t_hi) == :lt and Decimal.compare(t_lo, s_hi) == :lt

        %{base | status: :inconclusive}
        |> Map.put(:reason, :overlap)
        |> Map.put(:detail, %{touch?: not overlap?})
    end
  end

  defp verdict(base, relation, direction, exact?) do
    %{base | status: if(relation == direction, do: :favorable, else: :unfavorable)}
    |> Map.put(:reason, relation)
    |> Map.put(:detail, %{direction: direction, exact?: exact?})
  end

  # A published value as an operand: `{:exact, v}` or `{:range, low, high}`.
  defp operand(%{value_state: :exact, value: v}), do: {:exact, v}
  defp operand(%{value_state: :range, range_low: low, range_high: high}), do: {:range, low, high}

  defp interval({:exact, v}), do: {v, v}
  defp interval({:range, low, high}), do: {low, high}

  # A derived measure (e.g. Proficient + Advanced) from two published
  # components: exact only when both are exact; otherwise the sum of the
  # published bounds; `:not_derivable` when either is missing or suppressed.
  defp derived(levels, a, b) do
    x = levels[a]
    y = levels[b]

    if published?(x) and published?(y) do
      case {operand(x), operand(y)} do
        {{:exact, v}, {:exact, w}} ->
          {:exact, Decimal.add(v, w)}

        _ ->
          {:range, Decimal.add(bound(x, :low), bound(y, :low)),
           Decimal.add(bound(x, :high), bound(y, :high))}
      end
    else
      :not_derivable
    end
  end

  defp bound(%{value_state: :exact, value: v}, _), do: v
  defp bound(%{value_state: :range, range_low: low}, :low), do: low
  defp bound(%{value_state: :range, range_high: high}, :high), do: high

  defp published?(%{value_state: state}), do: state in [:exact, :range]
  defp published?(_), do: false

  defp value_text(%{value_state: :exact, unit: :proportion, value: v}), do: Percent.format(v)
  defp value_text(%{value_state: :exact, value: v}), do: Decimal.to_string(v, :normal)

  defp value_text(%{value_state: :range, range_low: low, range_high: high}),
    do: "#{Percent.format(low)}–#{Percent.format(high)}"

  defp value_text(%{value_state: :suppressed}), do: "suppressed"
  defp value_text(_), do: nil

  defp derived_text({:exact, v}), do: Percent.format(v)

  defp derived_text({:range, low, high}),
    do: "#{Percent.format(low)}–#{Percent.format(Decimal.min(high, Decimal.new(1)))}"

  defp derived_text(_), do: nil

  defp growth_label("DoesNotMeet"), do: "Does not meet"
  defp growth_label("OverallGrowthLevel"), do: "Overall growth level"
  defp growth_label("OverallGrowthPercentile"), do: "Overall growth percentile"
  defp growth_label(measure), do: measure

  # ── Section notes (dashboard and PDF) ─────────────────────────────────────

  @doc """
  Why a section's All Grades rows are context only:
  `[%{subject, school_grades, state_grades}]` for `:achievement` or `:growth`.
  """
  def coverage_notes(compared, section) do
    for {{subject, "All Grades"}, by} <-
          Enum.sort_by(compared[section], fn {{s, g}, _} -> SchoolResults.order_key(s, g) end),
        %{reason: :grade_coverage, detail: d} <- [
          Enum.find(Map.values(by), &(&1.reason == :grade_coverage))
        ] do
      %{subject: subject, school_grades: d.school_grades, state_grades: d.state_grades}
    end
  end

  @doc "One sentence per All Grades note, e.g. for the PDF."
  def coverage_sentence(%{subject: subject, school_grades: s, state_grades: t}),
    do:
      "#{subject_name(subject)} All Grades is context only: this school's All Grades covers grades #{grade_list(s)}; North Dakota's covers #{grade_list(t)}."

  @doc """
  The Engagement Survey benchmark status for the section header:
  `%{status: :compared | :not_compared, text}`.
  """
  def survey_note({:ok, brief}),
    do: %{
      status: :compared,
      summary:
        "Committed and Disengaged are compared with North Dakota middle-school respondents (grades 6–8) in the same year (#{brief.short}). Compliant isn't rated; Overall has no grade-span benchmark.",
      text:
        "Behavioral, Cognitive and Emotional Committed and Disengaged are compared with North Dakota middle-school respondents (grades 6–8) in the same year: #{brief.title}, Figure 5. The brief's Appendix C lists this school only under the middle-school version, and its % Committed for the school falls inside each published Insights range, so it is the same population. The Insights statewide row (grades 3–12) is shown for context only. Overall has no grade-span benchmark and Compliant is not rated."
    }

  def survey_note({:mixed_versions, brief, versions}),
    do: %{
      status: :not_compared,
      summary:
        "Not compared this year: this school's survey figure mixes survey versions (#{Enum.map_join(versions, " and ", fn {v, n, _} -> "#{v} #{n}" end)} respondents), and no published statewide figure covers that same mix. The Insights statewide row (grades 3–12) is a different population.",
      text:
        "Not compared for this year: the school's Insights survey figure includes respondents to more than one survey version (#{Enum.map_join(versions, " and ", fn {v, n, _} -> "#{v} #{n}" end)}; #{brief.title}, Appendix C), so neither the middle-school benchmark nor the Insights statewide row (grades 3–12) is the same population. A matching benchmark would need the statewide figure for that same mix, which is not published."
    }

  def survey_note({:does_not_reconcile, brief, domain}),
    do: %{
      status: :not_compared,
      summary:
        "Not compared this year: the technical brief's figures for this school don't match its published Insights #{domain_name(domain)} range, so the populations can't be confirmed as the same.",
      text:
        "Not compared for this year: #{brief.title} (Appendix C) does not reconcile with the published Insights #{domain_name(domain)} range for this school, so the populations can't be confirmed as the same."
    }

  def survey_note({:not_listed, brief}),
    do: %{
      status: :not_compared,
      summary:
        "Not compared this year: this school's survey population isn't recorded from the technical brief, so it can't be matched to a statewide benchmark.",
      text:
        "Not compared for this year: this school is not recorded from #{brief.title}, Appendix C, so its survey population can't be confirmed."
    }

  def survey_note({:no_brief, year}),
    do: %{
      status: :not_compared,
      summary:
        "Not compared for #{year}: no verified statewide grades 6–8 benchmark for that year. The Insights statewide row covers grades 3–12, a different population.",
      text:
        "Not compared for #{year}: no statewide middle-school (grades 6–8) benchmark from that year's ND Student Engagement Survey technical brief has been verified here, and the Insights statewide row covers grades 3–12."
    }

  # ── Legend (dashboard and PDF) ────────────────────────────────────────────

  @doc "The one-line legend summary kept visible on the dashboard and in the PDF."
  def legend_short,
    do:
      "Colors compare each published value with North Dakota for the same year (Engagement: ND grades 6–8 respondents). They are not school goal statuses."

  @doc "What the colors compare with (the legend's first paragraph)."
  def legend_intro,
    do:
      "Achievement and Growth are compared with the matching North Dakota row (same year, subject, grade, assessment type and student group). Engagement is compared only with a verified middle-school (grades 6–8) statewide benchmark from the same year. (% tested is checked against the 95% participation target beside the value, not here.) None of these is a school goal status: goal statuses are shown in the main result tables, the goal tables and Annual Targets."

  @doc "The legend's colors, as `[{tone, label}]`."
  def legend_items,
    do: [
      success: "Favorable: the whole published value is on that side",
      error: "Unfavorable: the whole published value is on that side",
      warning: "Cannot determine: the published values overlap or touch",
      neutral: "Matches: equal exact values",
      muted:
        "Gray: not compared (missing, suppressed, not rated, or a different population), with the reason"
    ]

  @doc "How published ranges are compared (the legend's last paragraph)."
  def published_values_note,
    do:
      "A comparison of published values: ranges are compared through their published low and high values, never midpoints. Insights converts identifiable data “to a range of values” but doesn't document rounding or whether 29% means “up to 29%” or “below 30%”, so a color is not a statement about the exact hidden value or an official determination."

  # ── Rows for the North Dakota comparison table ────────────────────────────

  @rated [
    achievement: [
      {"Novice", "Novice"},
      {"Advanced", "Advanced"},
      {:proficient_or_advanced, "Proficient or Advanced"}
    ],
    growth: [
      {"DoesNotMeet", "Does not meet"},
      {"Exceeds", "Exceeds"},
      {:meets_or_exceeds, "Meets or Exceeds"},
      {"OverallGrowthPercentile", "Overall growth percentile"}
    ],
    engagement: [{"Committed", "Committed"}, {"Disengaged", "Disengaged"}]
  ]

  @doc """
  The rated comparisons (only measures with a documented favorable
  direction) as table rows, in dashboard order:
  `[%{section, subject, grade, measure, school, state, status, tone, label, explanation}]`.
  Values the school didn't publish are left out.
  """
  def rows(%{achievement: _, growth: _, engagement: _} = compared) do
    areas = Map.new(SchoolResults.engagement_areas())

    for {section, measures} <- @rated,
        {key, by_measure} <- sort_keys(section, compared[section]),
        {measure, measure_label} <- measures,
        c = by_measure[measure],
        c != nil and c.reason != :school_unavailable do
      {subject, grade} = if section == :engagement, do: {areas[key], nil}, else: key

      %{
        section: section,
        subject: subject,
        grade: grade,
        measure: measure_label,
        school: c.school_text,
        state: c.state_text,
        status: c.status,
        tone: tone(c),
        label: status_label(c),
        explanation: explanation(c),
        print_explanation: print_explanation(c),
        benchmark: benchmark_line(c)
      }
    end
  end

  defp sort_keys(:engagement, by_area) do
    order = SchoolResults.engagement_areas() |> Enum.map(&elem(&1, 0))
    Enum.sort_by(by_area, fn {area, _} -> Enum.find_index(order, &(&1 == area)) end)
  end

  defp sort_keys(_section, by_key),
    do:
      Enum.sort_by(by_key, fn {{subject, grade}, _} -> SchoolResults.order_key(subject, grade) end)

  # ── Wording and tone (dashboard and PDF) ──────────────────────────────────

  @doc """
  The color family: `:success` (green), `:error` (red), `:warning` (yellow),
  `:neutral` (matches the state; outlined) or `:muted` (gray: not compared).
  """
  def tone(%{status: :favorable}), do: :success
  def tone(%{status: :unfavorable}), do: :error
  def tone(%{status: :inconclusive}), do: :warning
  def tone(%{status: :matches}), do: :neutral
  def tone(_comparison), do: :muted

  @doc "A short label shown in the table cell next to the value."
  def short_label(%{basis: :target, status: :favorable}), do: "Meets 95% participation target"
  def short_label(%{basis: :target, status: :unfavorable}), do: "Below 95% participation target"

  def short_label(%{basis: :target, status: :inconclusive}),
    do: "Cannot determine (95% participation target)"

  def short_label(%{basis: :band, status: :favorable}), do: "Favorable vs ND gr. 6–8"
  def short_label(%{basis: :band, status: :unfavorable}), do: "Unfavorable vs ND gr. 6–8"
  def short_label(%{basis: :band, status: :inconclusive}), do: "Overlaps ND gr. 6–8"
  def short_label(%{basis: :band, status: :matches}), do: "Matches ND gr. 6–8"
  def short_label(%{status: :favorable}), do: "Favorable vs ND"
  def short_label(%{status: :unfavorable}), do: "Unfavorable vs ND"
  def short_label(%{status: :inconclusive, detail: %{touch?: true}}), do: "Touches ND"
  def short_label(%{status: :inconclusive}), do: "Overlaps ND"
  def short_label(%{status: :matches}), do: "Matches state"

  def short_label(%{reason: reason})
      when reason in [:grade_coverage, :no_band_benchmark] or
             (is_tuple(reason) and elem(reason, 0) == :survey),
      do: "Context only"

  def short_label(%{reason: :intermediate}), do: "Intermediate level"
  def short_label(%{reason: :no_interpretation}), do: "No documented direction"

  def short_label(%{reason: {:no_target, _}}), do: "No participation target"
  def short_label(%{reason: :benchmark_unavailable}), do: "No ND value"
  def short_label(%{reason: :benchmark_suppressed}), do: "ND suppressed"
  def short_label(%{reason: :school_unavailable}), do: "Not compared"

  @doc """
  A compact label for narrow PDF cells. What it is compared with is given by
  the section and `benchmark_line/1`, so "vs ND" is left out.
  """
  def compact_label(%{basis: :target, status: :favorable}), do: "Meets 95% participation target"
  def compact_label(%{basis: :target, status: :unfavorable}), do: "Below 95% participation target"

  def compact_label(%{basis: :target, status: :inconclusive}),
    do: "Cannot determine (95% participation target)"

  def compact_label(%{status: :favorable}), do: "Favorable"
  def compact_label(%{status: :unfavorable}), do: "Unfavorable"
  def compact_label(%{status: :inconclusive, detail: %{touch?: true}}), do: "Touches"
  def compact_label(%{status: :inconclusive}), do: "Overlaps"
  def compact_label(%{status: :matches}), do: "Matches"
  def compact_label(%{reason: :intermediate}), do: "Intermediate"
  def compact_label(%{reason: :no_interpretation}), do: "No direction"
  def compact_label(c), do: short_label(c)

  @doc """
  The value the school was compared with, for print (no tooltips there):
  "ND 25%", "ND gr. 6–8 48.7%", "Target 95%", or nil.
  """
  def benchmark_line(%{reason: :school_unavailable}), do: nil
  def benchmark_line(%{basis: :target, reason: :target}), do: "Target 95%"

  def benchmark_line(%{basis: :band, detail: %{band: band}}),
    do: "ND gr. 6–8 #{Percent.format(band.value)}"

  def benchmark_line(%{reason: {:survey, _}, state_text: t}) when is_binary(t),
    do: "ND gr. 3–12 #{t}"

  def benchmark_line(%{reason: :no_band_benchmark, state_text: t}) when is_binary(t),
    do: "ND gr. 3–12 #{t}"

  def benchmark_line(%{state_text: t}) when is_binary(t), do: "ND #{t}"
  def benchmark_line(_c), do: nil

  @doc "The status as a full label (readable without color)."
  def status_label(%{reason: :grade_coverage, detail: d}),
    do:
      "Context only: grades differ (this school #{grade_list(d.school_grades)}; ND #{grade_list(d.state_grades)})"

  def status_label(%{reason: {:survey, _}}),
    do: "Context only: no matching middle-school survey benchmark this year"

  def status_label(%{reason: :no_band_benchmark}),
    do: "Context only: no grade-span benchmark for Overall"

  def status_label(%{reason: :intermediate}), do: "Intermediate level: published, not rated"

  def status_label(%{reason: :no_interpretation}),
    do: "No documented direction: published, not rated"

  def status_label(%{reason: :benchmark_unavailable}), do: "No North Dakota benchmark"
  def status_label(%{reason: :benchmark_suppressed}), do: "North Dakota value suppressed"
  def status_label(c), do: short_label(c)

  @doc "One or two sentences: the benchmark or target, and why the value has its color."
  def explanation(%{reason: :school_unavailable}),
    do: "No published school value (not published or suppressed), so nothing is compared."

  def explanation(%{reason: :benchmark_unavailable}),
    do:
      "Gray: no North Dakota row matches this year, subject, grade, assessment type and student group. " <>
        "Import a file with the state rows to compare."

  def explanation(%{reason: :benchmark_suppressed}),
    do: "Gray: the matching North Dakota value is suppressed, so there is no comparison."

  def explanation(%{reason: :intermediate} = c),
    do:
      "Gray: #{c.measure_label} is an intermediate level; a higher or lower share can mean students " <>
        "moved up or down, so it isn't rated.#{state_note(c)}"

  def explanation(%{reason: :no_interpretation} = c),
    do:
      "Gray: there is no documented favorable direction for #{c.measure_label} (Insights doesn't " <>
        "document what each level number stands for), so it isn't rated.#{state_note(c)}"

  def explanation(%{reason: :grade_coverage, detail: d} = c),
    do:
      "Gray, context only: All Grades covers different grades (this school " <>
        "#{grade_list(d.school_grades)}; North Dakota #{grade_list(d.state_grades)}), so the " <>
        "statewide figure is a different population.#{state_note(c)}"

  def explanation(%{reason: {:survey, survey}} = c),
    do:
      "Gray, context only. #{survey_note(survey).text}" <>
        if(c.state_text, do: " Insights statewide (grades 3–12): #{c.state_text}.", else: "")

  def explanation(%{reason: :no_band_benchmark} = c),
    do:
      "Gray, context only: the technical brief reports grade-span results for Behavioral, Cognitive " <>
        "and Emotional only, not Overall.#{state_note(c)}"

  def explanation(%{reason: {:no_target, :survey}}),
    do:
      "Gray: no documented target applies to survey participation, and it isn't compared with the state."

  def explanation(%{reason: {:no_target, which}}),
    do:
      "No participation target here: the 95% participation target (#{@target_source}) is compared only for ELA and math, " <>
        "all tested students (Combined assessment), All Grades. " <> no_target_reason(which)

  def explanation(%{basis: :target} = c) do
    why =
      case c.status do
        :favorable ->
          "Meets the 95% participation target: the published value's lower bound is at least 95%."

        :unfavorable ->
          "Below the 95% participation target: the published value's upper bound is below 95%."

        :inconclusive ->
          "Cannot determine against the 95% participation target: the published range crosses 95%."
      end

    "#{why} Published % tested: #{c.school_text}. Target: #{@target_source}. A dashboard comparison " <>
      "of published values, not an official compliance finding."
  end

  def explanation(%{reason: :equal} = c),
    do:
      "Neutral, #{short_label(c)}: school #{c.school_text} and #{benchmark_name(c)} #{c.state_text} were " <>
        "both published as exact values and are equal."

  def explanation(%{reason: :overlap} = c) do
    how =
      if c.detail[:touch?],
        do: "share an endpoint",
        else: "overlap"

    "Yellow, cannot determine: the published school value #{c.school_text} and #{benchmark_name(c)} " <>
      "#{c.state_text} #{how}, so the published values don't show which is higher.#{band_source(c)}"
  end

  def explanation(%{status: status, reason: relation, detail: %{direction: direction} = d} = c) do
    better = if direction == :higher, do: "Higher", else: "Lower"
    word = if relation == :higher, do: "above", else: "below"
    color = if status == :favorable, do: "Green", else: "Red"

    how =
      if d.exact?,
        do: "both published as exact values, and the school value is #{word} it",
        else: "the whole published school range is #{word} it"

    "#{color}, #{status}: school #{c.school_text}; #{benchmark_name(c)} #{c.state_text}; #{how}. " <>
      "#{better} #{c.measure_label} is favorable." <> @caveat <> band_source(c)
  end

  @doc """
  `explanation/1` without the general caveat and the benchmark source, for
  print, where both are given once in the appendix.
  """
  def print_explanation(c) do
    c
    |> explanation()
    |> String.replace(@caveat, "")
    |> String.replace(band_source(c), "")
  end

  defp benchmark_name(%{basis: :band}), do: "North Dakota middle-school respondents"
  defp benchmark_name(_c), do: "North Dakota"

  defp band_source(%{basis: :band, detail: %{brief: brief}}),
    do:
      " Benchmark: #{brief.title}, Figure 5 (same year, same survey version and classification)."

  defp band_source(_c), do: ""

  defp state_note(%{state_text: nil}), do: ""
  defp state_note(%{state_text: t}), do: " North Dakota: #{t}."

  defp no_target_reason(:subject),
    do: "The federal requirement covers reading/language arts and math, not science."

  defp no_target_reason(:assessment_type), do: "Select the Combined assessment to compare."

  defp no_target_reason(:subgroup),
    do:
      "Insights' student groups aren't verified as the federal subgroups, so they aren't compared."

  defp no_target_reason(:grade),
    do: "It applies to the school's tested students overall, not one grade."

  defp domain_name(area),
    do: area |> to_string() |> String.replace("engagement_", "") |> String.capitalize()

  defp subject_name("Reading"), do: "ELA (Reading)"
  defp subject_name(subject), do: subject

  defp grade_list([]), do: "none"
  defp grade_list(grades), do: Enum.join(grades, ", ")
end
