defmodule Emisint.Reports.School.NdFirstSchoolPdf do
  @moduledoc """
  Individual ND First school report (Typst via Imprintor, like the other
  school reports): goals and metrics with targets, the selected reporting
  period's actual results and implementation ratings, annual targets with the
  same comparison statuses as the dashboard, and official state results for
  the selected filters.

  All reads run as the requesting user in their tenant (`Dashboard`,
  `SchoolResults`), so a school the user cannot read is `{:error, :not_found}`.
  Values use the shared `Emisint.Improvement.Display` rules: missing,
  suppressed, ranged, unconfirmed and pending values keep their labels.
  """
  alias Emisint.Improvement.{
    Dashboard,
    Display,
    GoalStatus,
    GrowthPercentile,
    Payment,
    Percent,
    ResultGoals,
    Rubric
  }

  alias Emisint.NdInsights.{SchoolResults, StateComparison, SurveyBenchmark}

  @template_path "priv/typst/school/nd_first_school.typ"
  @privacy_note "To protect student privacy, data for populations with less than 10 students will not be displayed."

  @doc "Returns `{:ok, pdf_binary, filename}`, `{:error, :not_found}` or `{:error, reason}`."
  def generate(scope, slug, params \\ %{}) do
    with {:ok, data, filename} <- build(scope, slug, params) do
      template = File.read!(Application.app_dir(:emisint, @template_path))

      case Imprintor.compile_to_pdf(Imprintor.Config.new(template, data)) do
        {:ok, pdf} -> {:ok, pdf, filename}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc "The report data (also used by tests), plus the download file name."
  def build(scope, slug, params \\ %{}) do
    with {:ok, school} <- Dashboard.fetch_school(scope, slug),
         {:ok, defs} <- Dashboard.load_plan(scope, school) do
      period =
        Enum.find(defs.periods, &(&1.code == params["period"])) ||
          Dashboard.default_period(scope, school, defs.periods)

      data = Dashboard.load_period(scope, school, period)
      averages = Dashboard.seasonal_averages(defs.metrics, data.ratings)

      state =
        if school.state == "ND" and is_binary(school.state_entity_id),
          do: SchoolResults.load(scope.current_user, school.state_entity_id),
          else: SchoolResults.load(nil, nil)

      filters = SchoolResults.resolve_filters(state, params)
      benchmark = SchoolResults.load_benchmark(scope.current_user, filters.year)

      compared =
        if state.years != [], do: StateComparison.for_filters(state.rows, benchmark, filters)

      nd? = params["nd_comparison"] == "1"
      plan = %{school: school, metrics: defs.metrics, annual_goals: defs.annual_goals}
      config = ResultGoals.config(school)

      used = used_files(state.files, filters, cited_years(defs, state.rows))
      building? = match?(%{kind: :building}, Emisint.Improvement.Seeds.Participant.scope(school))

      report = %{
        report: %{
          title: "ND First school report",
          generated_at: Calendar.strftime(DateTime.utc_now(), "%b %-d, %Y %H:%M UTC"),
          generated_by: to_string(scope.current_user.email),
          period: if(building?, do: "Not applicable", else: period.label),
          period_scope:
            cond do
              building? ->
                "no workbook goals or seasonal ratings for this building"

              GrowthPercentile.review_period?(period) ->
                "review actuals and formal review ratings"

              true ->
                "seasonal actuals and ratings"
            end,
          state_year: filters.year || "No state data imported",
          state_type: type_label(filters.type),
          state_subgroup: subgroup_label(filters.subgroup),
          goal_reference: ResultGoals.reference_label(filters.reference),
          # Appended to the state results filters line; a building has no workbook goals.
          goal_reference_text:
            if(building?,
              do: "",
              else:
                " · goals compared with the #{ResultGoals.reference_label(filters.reference)} (reference)"
            )
        },
        school: %{
          name: school.name,
          district: school.district_name || "Not stated",
          state_id: "#{school.state} #{school.state_entity_id}",
          grades: school.grade_span || "Not stated in the sources",
          plan: defs.plan.name
        },
        payment: payment(defs.payment, defs.payment_estimates),
        averages:
          for(
            category <- [:systems, :student_outcome],
            do: average_row(category, averages[category], defs.plan.max_rating, period)
          ),
        rubric:
          for(
            {score, label, description} <- Rubric.levels(),
            do: %{
              score: "#{score}",
              label: label,
              description: description,
              tone: to_string(Display.score_tone(score))
            }
          ),
        goals: Enum.map(defs.goals, &goal(&1, defs, data, period, state.rows)),
        annual: annual_rows(defs.annual_goals, state.rows, config),
        annual_year_mapping: annual_year_mapping(config.annual_years),
        plan_targets: plan_targets(school),
        state: state_section(state, filters, benchmark, plan),
        nd_comparison: nd_comparison(state, filters, nd? && benchmark),
        scope: scope_section(school),
        guidance:
          config
          |> Map.put(:payment_configured?, defs.payment.terms.configured?)
          |> guidance()
          |> scope_guidance(school),
        appendix:
          compared
          |> appendix(nd?, config)
          |> then(
            &if(building?,
              do: Enum.reject(&1, fn line -> line =~ "Reference checkpoint." end),
              else: &1
            )
          ),
        sources: sources_used(defs.plan, used, compared, nd?),
        file_inventory: inventory_lines(state.files -- used),
        file_inventory_note: inventory_note(state.files, used)
      }

      {:ok, report, filename(school, period)}
    end
  end

  defp filename(school, period) do
    safe = fn s -> String.replace(s, ~r/[^a-zA-Z0-9_-]+/, "_") end
    "nd_first_#{safe.(school.slug)}_#{safe.(period.code)}.pdf"
  end

  # Same wording as the dashboard (`Improvement.Payment`). Every value is a
  # string, so the template never compares numbers.
  defp payment(p, estimates) do
    %{
      label: p.label,
      combined: Payment.combined_text(p.combined),
      terms: Payment.terms_text(p.terms),
      card_note:
        if(p.terms.configured?,
          do: "Provisional, not an actual payment. See “Estimated payment” below.",
          else: "No payment terms are set for this school. See “Estimated payment” below."
        ),
      terms_summary: Payment.terms_summary(p.terms),
      formula:
        "Estimate = #{p.formula}, capped at the checkpoint allocation and rounded to cents. Category averages are taken separately before the weights apply. Only formal 18- and 36-month review ratings count: seasonal ratings, targets and actual results never do. Every metric needs a review rating (an explicit 0 counts); otherwise the checkpoint stays “Awaiting review”. Estimates are not actual payments.",
      systems_count: "#{p.systems_metric_count}",
      outcomes_count: "#{p.outcomes_metric_count}",
      max_rating: "#{p.max_rating}",
      checkpoints:
        Enum.map(p.checkpoints, fn c ->
          %{
            label: c.label,
            systems_average: Payment.score_text(c.systems_average),
            outcomes_average: Payment.score_text(c.outcomes_average),
            weights: "#{Percent.format(c.systems_weight)} / #{Percent.format(c.outcomes_weight)}",
            weighted: Payment.score_text(c.weighted_score),
            allocation: Payment.money(c.allocation),
            estimate: Payment.status_text(c)
          }
        end),
      estimates:
        Enum.map(estimates, fn e ->
          "#{if e.checkpoint == :review_18m, do: "18-month review", else: "36-month review"}: #{Payment.money(e.amount)} · #{e.label} · recorded #{Calendar.strftime(e.recorded_at, "%b %-d, %Y")} · terms v#{e.terms_version} (#{e.terms_status}): cap #{Payment.money(e.payment_cap)}, allocation #{Payment.money(e.allocation)}, weights #{Percent.format(e.systems_weight)} / #{Percent.format(e.outcomes_weight)}, averages #{Payment.score_text(e.systems_average)} / #{Payment.score_text(e.outcomes_average)}, weighted #{Payment.score_text(e.weighted_score)}, #{length(e.inputs)} ratings"
        end)
    }
  end

  defp average_row(category, a, _max, %{kind: kind}) when kind in [:review_18m, :review_36m] do
    %{
      category: category_label(category),
      average: "#{a.rated} of #{a.total} scored",
      coverage:
        "Formal review ratings: the payment input. Averages appear in the estimated payment once every rating is recorded."
    }
  end

  defp average_row(category, a, max, _period) do
    %{
      category: category_label(category),
      average: if(a.average, do: "#{a.average} / #{max}", else: "Not rated"),
      coverage:
        "#{a.rated} of #{a.total} metrics rated. Seasonal ratings are progress checks, not payment inputs."
    }
  end

  defp goal(goal, defs, data, period, state_rows) do
    metrics = Map.get(defs.metrics_by_goal, goal.id, [])
    flagged = Enum.filter(metrics, &(:review_18m_column_heading_unconfirmed in &1.flags))

    %{
      title: "Goal #{goal.number}: #{goal.title}",
      description: Display.goal_description(goal.description) || "",
      steps:
        case goal.implementation_steps[period.code] do
          nil ->
            "No implementation steps recorded for #{period.label}."

          n ->
            "#{n} planned implementation #{if n == 1, do: "step", else: "steps"} in #{period.label} (step wording is not in the source workbook)."
        end,
      review_note:
        if(flagged == [],
          do: "",
          else:
            "Needs confirmation: this goal's 18-month column in the workbook is headed “Target Check”, not “18-Month Review Rating”. The workbook's payment formula averages that whole column, so a 0–3 rating entered there for " <>
              Enum.map_join(flagged, ", ", & &1.code) <>
              " would count as a review rating. The provisional estimate follows that formula, so it expects a formal review rating for these metrics too; whether the column holds review ratings is still to confirm. Targets and actual results are not ratings and never produce a payment on their own."
        ),
      metrics: Enum.map(metrics, &metric_row(&1, data, period, state_rows))
    }
  end

  defp metric_row(metric, data, period, state_rows) do
    actual = data.actuals[metric.id]
    rating = data.ratings[metric.id]
    status = GoalStatus.evaluate(metric, actual, period)

    %{
      code: metric.code,
      description: metric.description,
      category: category_label(metric.category),
      direction: if(metric.direction == :lower_is_better, do: "Lower is better", else: ""),
      unit: Display.unit_label(metric) || "",
      source_note: insights_note(metric, state_rows),
      baseline: target_text(metric, :baseline_value),
      target_18m: target_text(metric, :target_18m),
      target_36m: target_text(metric, :target_36m),
      actual: Display.actual(actual, metric),
      status: GoalStatus.summary(status) || "",
      status_tone: goal_tone(status.status),
      actual_source: provenance(actual, data.users),
      rating: Display.rating(rating),
      rating_tone: to_string(Display.rating_tone(rating)),
      rating_source: provenance(rating, data.users)
    }
  end

  # Same wording as the dashboard: the mapped measure, and the latest
  # published year as reference only.
  defp insights_note(metric, state_rows) do
    case GrowthPercentile.mapping(metric) do
      nil ->
        ""

      m ->
        latest =
          case state_rows |> GrowthPercentile.published(metric) |> List.first() do
            nil ->
              "No published value imported."

            row ->
              "Published #{row.academic_year}: #{state_value(row)} (reference only; not a result for this period)."
          end

        "ND Insights source: Overall Growth Percentile · #{m["subject"]} · All Grades · All students. " <>
          latest
    end
  end

  defp target_text(metric, field) do
    case Display.target(metric, field) do
      {:number, text} -> text
      {:text, text} -> "“#{text}” (as written)"
      {:date, _} -> "Needs confirmation (cell holds a date)"
      {:needs_confirmation, _} -> confirmation_text(metric, field)
      {:empty, text} -> text
    end
  end

  defp confirmation_text(metric, field) do
    case Display.target_source(metric, field) do
      %{cell: cell, raw: raw} when is_binary(raw) -> "Needs confirmation (#{cell} lists #{raw})"
      _ -> "Needs confirmation"
    end
  end

  defp provenance(nil, _users), do: ""

  defp provenance(%{source: :workbook_import} = e, _users),
    do: "[W] #{e.source_ref}"

  defp provenance(%{source: :nd_insights} = e, users) do
    who = Map.get(users, e.author_id, "unknown")
    prefix = if e.kind == :correction, do: "Correction: ", else: ""

    year = GrowthPercentile.source_year(e) || "unknown"

    "#{prefix}Source year #{year}. #{e.source_ref}; selected by #{who}, #{Calendar.strftime(e.recorded_at, "%b %-d, %Y")}"
  end

  defp provenance(%{source: :unit_conversion} = e, users) do
    who = Map.get(users, e.author_id, "unknown")

    "Unit correction (growth percentile), restated #{Calendar.strftime(e.recorded_at, "%b %-d, %Y")}; originally submitted by #{who}"
  end

  defp provenance(e, users) do
    who = Map.get(users, e.author_id, "unknown")
    prefix = if e.kind == :correction, do: "Corrected by ", else: "Submitted by "
    "#{prefix}#{who}, #{Calendar.strftime(e.recorded_at, "%b %-d, %Y")}"
  end

  defp annual_rows(goals, rows, config) do
    goals
    |> Enum.group_by(& &1.school_year)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {year, list} ->
      by = Map.new(list, &{&1.subject, &1})
      ela = by[:ela] && ResultGoals.annual(by[:ela], rows, config)
      math = by[:math] && ResultGoals.annual(by[:math], rows, config)

      %{
        year: year,
        ela_goal: by[:ela] && Percent.format(by[:ela].target_value),
        ela_published: ela && annual_text(ela),
        ela_tone: annual_tone(ela),
        math_goal: by[:math] && Percent.format(by[:math].target_value),
        math_published: math && annual_text(math),
        math_tone: annual_tone(math)
      }
    end)
  end

  # Same comparison and wording as the dashboard's Annual Targets table and
  # state tables (`ResultGoals.annual/2`).
  defp annual_tone(%{status: status}) when status in [:not_published, :year_unconfirmed],
    do: "neutral"

  defp annual_tone(%{tone: tone}), do: to_string(tone)
  defp annual_tone(nil), do: "neutral"

  @doc "An Annual Targets cell as text."
  def annual_text(%{status: :not_published} = m),
    do: m[:missing] || "No matching results in the imported data"

  def annual_text(%{status: :year_unconfirmed} = m), do: m.missing

  def annual_text(m),
    do: "#{m.value || "Not derivable"} derived · #{ResultGoals.short_label(m)}"

  defp interval(%{low: low, high: high}) do
    if Decimal.equal?(low, high),
      do: Percent.format(low),
      else: "#{Percent.format(low)}–#{Percent.format(high)}"
  end

  # The optional North Dakota comparison (only when the export asks for it):
  # the dashboard's rated comparisons as rows.
  defp nd_comparison(_state, _filters, false), do: %{included: false}
  defp nd_comparison(%{years: []}, _filters, _benchmark), do: %{included: false}

  defp nd_comparison(state, f, benchmark) do
    compared = StateComparison.for_filters(state.rows, benchmark, f)

    %{
      included: true,
      legend: legend(compared.benchmark?, f.year),
      coverage:
        for(
          {section, label} <- [achievement: "Achievement", growth: "Growth"],
          n <- StateComparison.coverage_notes(compared, section),
          do: "#{label}: " <> StateComparison.coverage_sentence(n)
        ),
      engagement_benchmark:
        if(SchoolResults.engagement(state.rows, f.year) == [],
          do: "",
          else: "Engagement: " <> StateComparison.survey_note(compared.survey_benchmark).summary
        ),
      note:
        if(compared.benchmark?,
          do:
            "Every rated measure, with the matching statewide value (same year, subject, grade, assessment type and student group) and the reason for its color. Only lower Novice, Does not meet and Disengaged, and higher Advanced, Proficient or Advanced, Exceeds, Meets or Exceeds, Overall growth percentile and Committed are rated. This compares published values; it is not a goal result or a test of statistical significance.",
          else:
            "No North Dakota benchmark rows have been imported for #{f.year}, so nothing is compared."
        ),
      rows:
        if(compared.benchmark?,
          do:
            compared
            |> StateComparison.rows()
            |> Enum.map(fn r ->
              %{
                section: r.section |> to_string() |> String.capitalize(),
                subject: subject_label(r.subject),
                grade: r.grade || "",
                measure: r.measure,
                school: r.school,
                state: (r.benchmark && String.replace_prefix(r.benchmark, "ND ", "")) || "—",
                label: r.label,
                explanation: r.print_explanation,
                tone: to_string(r.tone)
              }
            end),
          else: []
        )
    }
  end

  defp goal_tone(:meets), do: "success"
  defp goal_tone(:below), do: "error"
  defp goal_tone(_), do: "neutral"

  defp state_section(%{years: []}, _filters, _benchmark, _plan), do: %{has_data: false}

  defp state_section(state, f, benchmark, plan) do
    perf = SchoolResults.performance(state.rows, f.year, f.type, f.subgroup)
    growth = SchoolResults.growth(state.rows, f.year, f.subgroup)
    engagement = SchoolResults.engagement(state.rows, f.year)
    compared = StateComparison.for_filters(state.rows, benchmark, f)
    goals = ResultGoals.for_filters(state.rows, f, plan)
    config = ResultGoals.config(plan.school)
    goal_years = plan.annual_goals |> Enum.map(& &1.school_year) |> Enum.uniq()

    %{
      has_data: true,
      legend: %{
        intro: ResultGoals.legend_short(),
        # No workbook goals (a building record): no reference checkpoint to explain.
        reference: if(plan.metrics == [], do: "", else: ResultGoals.reference_note(f.reference)),
        items:
          Enum.map(ResultGoals.legend_items(), fn {tone, label} ->
            %{tone: to_string(tone), label: label}
          end)
      },
      notes: %{
        achievement:
          ResultGoals.section_notes(:achievement, goals.achievement) ++
            List.wrap(config.section_notes[:achievement]) ++
            if(
              f.type != "Comp" and plan.metrics != [] and
                config.assumptions[:assessment_type] == "Comp",
              do: [
                "Workbook targets are compared only in the Combined assessment view (demo assumption)."
              ],
              else: []
            ),
        growth: ResultGoals.section_notes(:growth, goals.growth),
        engagement: ResultGoals.section_notes(:engagement, goals.engagement),
        # Which workbook metrics each table is matched to (the school's own).
        growth_matching: config.section_notes[:growth] || "",
        engagement_matching: config.section_notes[:engagement] || ""
      },
      goal_years_note:
        if(goal_years != [] and f.year not in goal_years,
          do:
            ResultGoals.annual_years_note(goal_years, f.year) <>
              if(plan.metrics == [],
                do: "",
                else:
                  " Workbook goals are compared with the #{ResultGoals.reference_label(f.reference)} as a reference."
              ),
          else: ""
        ),
      achievement:
        Enum.map(perf, fn r ->
          g = goals.achievement[{r.subject, r.grade}]
          v = &goal_cell(state_value(r.levels[&1]), g[&1])

          %{
            subject: subject_label(r.subject),
            grade: r.grade,
            novice: v.("Novice"),
            partially: v.("Partially"),
            proficient: v.("Proficient"),
            advanced: v.("Advanced"),
            derived:
              if(r.levels == %{},
                do: goal_cell("Not published", nil),
                else: goal_cell(derived(r.proficient_or_advanced), g[:proficient_or_advanced])
              ),
            tested:
              participation_cell(
                state_value(r.tested),
                compared.achievement[{r.subject, r.grade}]["PercentTested"]
              )
          }
        end),
      # "" when achievement levels are published. Rows with only % tested are
      # still listed above, so participation stays visible.
      achievement_empty:
        if(SchoolResults.achievement_published?(perf),
          do: "",
          else:
            "No published achievement results for #{type_label(f.type)} assessment · #{subgroup_label(f.subgroup)} · #{f.year}; the imported state download has no achievement rows for this combination." <>
              if(perf != [],
                do: " % tested is shown where the participation download publishes it.",
                else: ""
              ) <>
              latest_year_text(
                SchoolResults.latest_year_with(state.rows, :achievement, f),
                "achievement"
              )
        ),
      growth:
        Enum.map(growth, fn r ->
          g = goals.growth[{r.subject, r.grade}]
          v = &goal_cell(state_value(r.levels[&1]), g[&1])

          %{
            subject: subject_label(r.subject),
            grade: r.grade,
            does_not_meet: v.("DoesNotMeet"),
            approaches: v.("Approaches"),
            meets: v.("Meets"),
            exceeds: v.("Exceeds"),
            derived: goal_cell(derived(r.meets_or_exceeds), nil),
            level: v.("OverallGrowthLevel"),
            percentile: v.("OverallGrowthPercentile")
          }
        end),
      # "" when growth is published (the template prints it only for an empty table).
      growth_empty:
        if(growth == [],
          do:
            "No published growth results for #{subgroup_label(f.subgroup)} · #{f.year}; the imported state growth download has no rows for this combination." <>
              latest_year_text(SchoolResults.latest_year_with(state.rows, :growth, f), "growth"),
          else: ""
        ),
      engagement:
        Enum.map(engagement, fn r ->
          g = goals.engagement[r.area]
          v = &goal_cell(state_value(r.levels[&1]), g[&1])

          %{
            area: r.label,
            committed: v.("Committed"),
            compliant: v.("Compliant"),
            disengaged: v.("Disengaged")
          }
        end),
      engagement_empty: "No published Engagement Survey results for #{f.year}.",
      participation: survey_participation(SchoolResults.survey_participation(state.rows, f.year))
    }
  end

  # A published value with its matching school goal (same wording as the
  # dashboard): tone "success", "error", "warning" or "muted" (gray) fills
  # the cell; "none" (no goal) stays plain.
  defp goal_cell(text, nil),
    do: %{text: text, tone: "none", fill: "false", label: "", caveat: "", line: ""}

  defp goal_cell(text, m),
    do: %{
      text: text,
      tone: to_string(m.tone),
      fill: "true",
      label: ResultGoals.short_label(m),
      caveat: "",
      line: ResultGoals.goal_line(m)
    }

  # % tested with the 95% participation target as a label only: never a goal
  # status, so the cell isn't filled.
  # Shown only where the target applies (ELA and math, Combined, all
  # students, All Grades); the table note says so.
  defp participation_cell(text, %{reason: :target} = c),
    do: %{
      text: text,
      tone: to_string(StateComparison.tone(c)),
      fill: "false",
      label: StateComparison.compact_label(c),
      caveat: "",
      line: ""
    }

  defp participation_cell(text, _c), do: goal_cell(text, nil)

  defp legend(benchmark?, year) do
    %{
      intro:
        StateComparison.legend_short() <>
          if(benchmark?,
            do: "",
            else: " No North Dakota benchmark rows are imported for #{year}, so values are gray."
          ),
      items:
        Enum.map(StateComparison.legend_items(), fn {tone, label} ->
          %{tone: to_string(tone), label: label}
        end)
    }
  end

  defp survey_participation(nil), do: "Not published for this year."

  defp survey_participation(%{status: :consistent, result: r, rows: rows}),
    do:
      "#{state_value(r)} of enrolled students took the survey (identical on the download's #{length(rows)} source rows). No goal or target applies."

  defp survey_participation(%{status: :inconsistent, rows: rows}),
    do:
      "Source rows disagree and are not combined: " <>
        Enum.map_join(rows, "; ", &"#{&1.engagement_level} row #{state_value(&1)}")

  defp state_value(nil), do: "Not published"
  defp state_value(%{value_state: :suppressed}), do: "Suppressed"
  defp state_value(%{value_state: :exact, unit: :proportion, value: v}), do: Percent.format(v)
  defp state_value(%{value_state: :exact, value: v}), do: Decimal.to_string(v, :normal)

  defp state_value(%{value_state: :range, range_low: l, range_high: h}),
    do: "#{Percent.format(l)}–#{Percent.format(h)}"

  # Same wording as the dashboard's latest-year link (the PDF names the year).
  defp latest_year_text(nil, what),
    do: " No imported year has #{what} results for this combination."

  defp latest_year_text(year, what),
    do: " Latest imported year with #{what} results for the same filters: #{year}."

  defp derived({:ok, low, high}), do: interval(%{low: low, high: high})
  defp derived({:not_derivable, _}), do: "Not derivable"

  # Insights files this report's tables draw on: the selected year (and the
  # Engagement files, which hold every year) and the growth-percentile year
  # cited in the goal tables.
  defp used_files(files, filters, cited_years) do
    years = Enum.uniq([filters.year | cited_years])

    Enum.filter(files, fn f ->
      engagement?(f.dataset) or
        Enum.any?(years, &(is_binary(&1) and String.contains?(f.file_name, &1)))
    end)
  end

  # Sources this report's tables actually draw on: the workbook and plan PDF,
  # the Insights files used, the survey brief when it is used, and the
  # participation statute.
  defp sources_used(plan, used, compared, nd?) do
    [
      # [W] marks the goal workbook; a building's plan cites only the PDF.
      if(String.starts_with?(plan.source_note || "", "ND First School MOU Goal Overview"),
        do: "[W] " <> plan.source_note,
        else: plan.source_note
      ),
      "Annual targets: North Dakota - ND First Schools.pdf (each school's continuous improvement plan page)."
    ] ++
      Enum.map(used, &file_line/1) ++
      case nd? && compared && compared.survey_benchmark do
        {:ok, brief} -> ["Engagement benchmark: " <> SurveyBenchmark.source(brief)]
        _ -> []
      end ++
      if(target_compared?(compared),
        do: [
          "95% participation target: 20 U.S.C. 6311(c)(4)(E)(i), https://www.law.cornell.edu/uscode/text/20/6311"
        ],
        else: []
      ) ++
      if(nd? and compared != nil,
        do: [
          "Benchmark evidence and reproduction steps: docs/nd_insights_benchmarks.md (project repository)"
        ],
        else: []
      )
  end

  # School years whose published growth percentile the goal tables cite.
  defp cited_years(defs, rows) do
    for metric <- defs.metrics,
        GrowthPercentile.mapping(metric),
        %{academic_year: year} <- [rows |> GrowthPercentile.published(metric) |> List.first()],
        uniq: true,
        do: year
  end

  defp target_compared?(nil), do: false

  defp target_compared?(compared),
    do:
      Enum.any?(compared.achievement, fn {_, by} ->
        match?(%{reason: :target}, by["PercentTested"])
      end)

  defp file_line(f),
    do:
      "ND Insights: #{f.file_name} (version #{f.publication_version}, sha256 #{String.slice(f.sha256, 0, 12)}…)"

  # The inventory lists only the files not already cited under "Sources used
  # in this report", so no file is printed twice.
  defp inventory_note(files, used) do
    case length(files) - length(used) do
      0 ->
        "All #{length(files)} ND Insights files imported for this school are listed under “Sources used in this report”."

      other ->
        "#{length(files)} ND Insights files are imported for this school: the #{length(used)} under “Sources used in this report”, and the #{other} below, listed for reference only; they do not feed this report's tables. Each file is named Insights-‹download›-CSV-‹school year›-v‹version›.csv; the hex value after each version is the start of the file's SHA-256 hash."
    end
  end

  @yearly_file ~r/^Insights-(?<download>.+)-CSV-(?<year>\d{4}-\d{4})-v(?<version>\d+)\.csv$/

  # One line per download, each school year with its version and hash, so
  # the reference list stays short. A file not named by the yearly pattern
  # keeps its own full line.
  defp inventory_lines(files) do
    {yearly, other} =
      files
      |> Enum.map(&{&1, Regex.named_captures(@yearly_file, &1.file_name)})
      |> Enum.split_with(fn {_, captures} -> captures end)

    grouped =
      yearly
      |> Enum.group_by(fn {_, c} -> c["download"] end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {download, entries} ->
        years =
          entries
          |> Enum.sort_by(fn {_, c} -> c["year"] end)
          |> Enum.map_join("; ", fn {f, c} ->
            "#{c["year"]} v#{c["version"]} #{String.slice(f.sha256, 0, 12)}…"
          end)

        "#{download}: #{years}"
      end)

    grouped ++ Enum.map(other, fn {f, _} -> file_line(f) end)
  end

  defp engagement?(dataset), do: dataset |> to_string() |> String.starts_with?("engagement")

  # Short guidance printed after the results; methodology is in the appendix.
  defp guidance(config) do
    [
      "Goal tables: “Not reported” means no actual result has been submitted for this period; “Not rated” means no implementation rating has been submitted. Neither is zero.",
      "Goal status: green “Meets target” or red “Below target” only at the review whose target is due (18-month target at the 18-Month Review, 36-month target at the 36-Month Review), respecting whether the metric should rise or fall. Seasonal periods have no target due. Ratings use the 0–3 rubric colors.",
      payment_guidance(config),
      "Official state results are compared with the school's goals through their published low and high values: green “Meets target”, red “Below target” (“Above target” when lower is better), amber “Range overlaps target”. Equal meets. A dashboard comparison rule, not an official ND FIRST scoring method.",
      "Workbook goals are compared with the selected reference target (18- or 36-month) and labeled “Reference comparison against future target” or “Reference comparison — review year unconfirmed”. They never record review results, set ratings or affect the payment estimate.",
      Enum.join(
        Enum.reject(
          [
            config.assumptions_short,
            "Gray: missing or suppressed values, missing targets, or known incompatible comparisons. No shading: no school goal for that measure."
          ],
          &is_nil/1
        ),
        " "
      ),
      "% tested shows the 95% participation target as a label only; it is not a school goal. North Dakota comparisons appear only in the optional “North Dakota comparison” export.",
      config.annual_note,
      "[W] marks values imported from the goal workbook (cell shown); see the appendix."
    ]
    |> Enum.reject(&is_nil/1)
  end

  # Same wording as the dashboard (`Components.annual_year_mapping/1`).
  defp annual_year_mapping(nil), do: ""

  defp annual_year_mapping(%{status: :confirmed} = y),
    do:
      "Year mapping confirmed by the user: the targets are 2025–2026 through 2030–2031, in order (recorded November 8, 2026). Source wording: #{y.excerpt} (#{y.location})"

  defp annual_year_mapping(%{status: :stated} = y),
    do: "Year mapping as stated in the source: #{y.excerpt} (#{y.location})"

  defp annual_year_mapping(%{status: :assumed} = y),
    do:
      "Year mapping unconfirmed: the source assumes which school year each target belongs to, so year-specific comparisons are off until the years are confirmed. Source: #{y.excerpt} (#{y.location})"

  # Other plan targets (`Improvement.PlanTargets`), as strings for the
  # template. Never compared with a result.
  defp plan_targets(school) do
    school
    |> Emisint.Improvement.PlanTargets.for_school()
    |> Enum.map(fn t ->
      %{
        title: t.title,
        status: to_string(t.status),
        status_label: Emisint.Improvement.PlanTargets.status_label(t.status),
        measure: t.measure,
        baseline: (t.baseline && "Baseline: " <> t.baseline) || "",
        targets: Enum.map_join(t.targets, " · ", fn {label, value} -> "#{label}: #{value}" end),
        long_term: t.long_term || "",
        status_note: t.status_note,
        results_note: t.results_note,
        location: "Source: " <> t.location
      }
    end)
  end

  # Where the record sits among the ND First participants (`Seeds.Participant`):
  # "participant" (district), "building" or "school". A building's report
  # omits the workbook goals, seasonal averages and payment, which belong to
  # its participant. Same wording as the dashboard.
  defp scope_section(school) do
    scope = Emisint.Improvement.Seeds.Participant.scope(school)
    provisional? = Emisint.Improvement.Seeds.Participant.provisional_scope?(scope)

    # Warwick: the workbook's scope is not established, so it is never stated as fact.
    provisional =
      if provisional?,
        do: scope.workbook_scope.note <> " Source: " <> scope.workbook_scope.excerpt,
        else: ""

    case scope do
      %{kind: :participant, buildings: buildings} ->
        names = Enum.map_join(buildings, ", ", & &1.school().name)

        %{
          kind: "participant",
          note:
            "District participant. The ND First workbook goals, seasonal ratings and payment in this report are " <>
              if(provisional?,
                do: "recorded on #{school.name} provisionally (see the scope note below)",
                else: "written for #{school.name}"
              ) <>
              ", and the state results are the district's own published rows (InstitutionID #{school.state_entity_id}). Annual targets are set per building and reported on each building's report: #{names}.",
          provisional: provisional,
          annual_empty:
            "No annual targets are set for the district: the continuous improvement plan sets them per building (#{names}). See each building's report."
        }

      %{kind: :building, participant: participant} ->
        %{
          kind: "building",
          note:
            "Building of an ND First participant. This report shows #{school.name}'s own annual targets and published results. The ND First workbook goals, seasonal ratings and payment are " <>
              if(provisional?,
                do:
                  "recorded provisionally on #{participant.school().name}; whether they cover this building is not established by the sources. They are in that report, not repeated here.",
                else:
                  "written for #{participant.school().name} and are in its report, not repeated here."
              ),
          provisional: provisional,
          annual_empty: "No annual targets are recorded for this building."
        }

      _ ->
        %{
          kind: "school",
          note: "",
          provisional: "",
          annual_empty: "No annual targets are recorded for this school."
        }
    end
  end

  # A building's report has no goal tables or payment, so their guidance is left out.
  defp scope_guidance(items, school) do
    case Emisint.Improvement.Seeds.Participant.scope(school) do
      %{kind: :building} ->
        Enum.reject(
          items,
          &String.starts_with?(&1, [
            "Goal tables",
            "Goal status",
            "Estimated payment",
            "Workbook goals",
            "[W]"
          ])
        )

      _ ->
        items
    end
  end

  defp payment_guidance(%{payment_configured?: false}),
    do:
      "Estimated payment — not configured: this school's payment terms are not set, so no estimate is calculated. Only formal 18- and 36-month review ratings would count."

  defp payment_guidance(_config),
    do:
      "Estimated payment — provisional cap and split: only formal 18- and 36-month review ratings count. Target values, actual results and seasonal ratings never produce a payment on their own. The cap and split are provisional; see the appendix."

  # Detailed methodology, printed as an appendix.
  defp appendix(compared, nd?, config) do
    Enum.map(ResultGoals.methodology(config), &("School goals. " <> &1)) ++
      [
        "Published values. Values are shown as published: exact, a range (never a midpoint) or suppressed. Proficient or Advanced and Meets or Exceeds add the two published components (derived; not published by the state).",
        "95% participation target. 20 U.S.C. 6311(c)(4)(E)(i) requires measuring at least 95% of all students on the reading/language arts and mathematics assessments; Insights' participation charts note the same 95%. Checked only for ELA and math, Combined assessment, all students, All Grades. A dashboard check of published values, not an official compliance finding."
      ] ++
      nd_methodology(compared, nd?) ++
      [
        "Annual targets table. Matched to the same year, subject, Combined assessment, all grades and all students, and compared by the same dashboard rule as the state results, so the two always agree. Another year's target is never substituted."
      ] ++
      config.report_notes ++
      [
        "“Not published” means the state's download has no row for that group. Insights notes: “#{@privacy_note}”"
      ]
  end

  # North Dakota comparison methodology, only when that section is exported.
  defp nd_methodology(%{survey_benchmark: survey}, true),
    do: [
      "North Dakota comparison. " <> StateComparison.published_values_note(),
      "North Dakota matching. A North Dakota value is used only for the same year, subject, grade, assessment type, student group, accommodations and measure. All Grades rows are compared only when the school and the state cover the same grades.",
      "North Dakota directions. Higher is favorable: Advanced, Proficient or Advanced, Exceeds, Meets or Exceeds, Overall growth percentile, Committed. Lower is favorable: Novice, Does not meet, Disengaged. Approaching Proficiency (download column “Partially”), Proficient alone, Approaches, Meets, Compliant and the overall growth level are not rated.",
      "Engagement benchmark. " <> StateComparison.survey_note(survey).text
    ]

  defp nd_methodology(_compared, _nd?), do: []

  defp category_label(:systems), do: "Systems"
  defp category_label(:student_outcome), do: "Student Outcome"

  defp subject_label("Reading"), do: "ELA (Reading)"
  defp subject_label(s), do: s

  defp type_label(code) do
    case List.keyfind(SchoolResults.assessment_types(), code, 0) do
      {_, label} -> label
      nil -> code || "—"
    end
  end

  defp subgroup_label("All"), do: "All students"
  defp subgroup_label(nil), do: "—"
  defp subgroup_label(s), do: s
end
