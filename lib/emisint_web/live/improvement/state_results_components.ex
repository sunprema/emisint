defmodule EmisintWeb.Improvement.StateResultsComponents do
  @moduledoc """
  Official ND Insights results for a school: achievement (with Proficient
  alone and the derived Proficient-or-Advanced range shown separately),
  participation, growth and the Engagement Survey, plus source files.

  Values are shown as published: exact, a range (never a midpoint) or
  "Suppressed". A group the state did not publish is "Not published".
  These are annual results and are never tied to a seasonal period.

  Colors in the main tables show the school's own goals
  (`Improvement.ResultGoals`); % tested shows the 95% participation target as
  a label only. North Dakota comparisons are only in the separate, collapsed
  "North Dakota comparison" section (`NdInsights.StateComparison`).
  """
  use EmisintWeb, :html

  alias Emisint.Improvement.{Percent, ResultGoals}
  alias Emisint.NdInsights.{SchoolResults, StateComparison}

  @insights_data "https://insights.nd.gov/Data"
  @privacy_note "To protect student privacy, data for populations with less than 10 students will not be displayed."

  attr :match, :map, required: true, doc: "`ResultGoals.annual/2`"

  # An Annual Targets cell: the same comparison as the state tables.
  def goal_comparison(%{match: %{status: :year_unconfirmed}} = assigns) do
    ~H"""
    <span class="text-base-content/60 italic" data-status="year_unconfirmed">{@match.missing}</span>
    """
  end

  def goal_comparison(%{match: %{status: :not_published}} = assigns) do
    ~H"""
    <span class="text-base-content/50 italic">
      {@match[:missing] || "No matching results in the imported data"}
    </span>
    """
  end

  def goal_comparison(assigns) do
    ~H"""
    <div class={["rounded px-1.5 py-1", "nd-cell-#{@match.tone}"]} data-status={@match.status}>
      <span class="font-semibold">{@match.value || "Not derivable"}</span>
      <span class="badge badge-outline badge-xs ml-1">Derived</span>
      <div class={["text-xs font-medium", goal_text(@match.tone)]}>
        <span aria-hidden="true">{goal_symbol(@match.tone)}</span>
        {ResultGoals.short_label(@match)}
      </div>
      <div class="text-xs text-base-content/60">
        Proficient + Advanced, Combined assessment, All Grades, all students · same-year target {@match.target.text}
      </div>
    </div>
    """
  end

  attr :school, :map, required: true
  attr :state, :map, required: true
  attr :filters, :map, required: true
  attr :metrics, :list, default: [], doc: "the plan's metrics (workbook goals)"
  attr :annual_goals, :list, default: [], doc: "the school's annual assessment goals"
  attr :import_path, :string, default: nil, doc: "ND Insights import link; shown only when set"

  attr :comparison_pdf_path, :string, default: nil, doc: "PDF export including the comparison"

  attr :link_params, :map,
    default: %{},
    doc:
      "the dashboard's current query params; kept by the latest-year links (only the year changes)"

  attr :benchmark_rows, :list,
    default: [],
    doc: "the year's North Dakota benchmark rows (SchoolResults.load_benchmark/2)"

  def state_results(assigns) do
    %{rows: rows} = assigns.state
    %{year: year, type: type, subgroup: subgroup} = assigns.filters

    assigns =
      assign(assigns,
        compared: StateComparison.for_filters(rows, assigns.benchmark_rows, assigns.filters)
      )

    assigns = assign(assigns, config: ResultGoals.config(assigns.school))

    assigns =
      assign(assigns,
        goals:
          ResultGoals.for_filters(rows, assigns.filters, %{
            school: assigns.school,
            metrics: assigns.metrics,
            annual_goals: assigns.annual_goals
          }),
        annual_goal_years: assigns.annual_goals |> Enum.map(& &1.school_year) |> Enum.uniq()
      )

    assigns =
      assign(assigns,
        comparison_rows:
          if(assigns.compared.benchmark?, do: StateComparison.rows(assigns.compared), else: [])
      )

    performance = SchoolResults.performance(rows, year, type, subgroup)
    growth = SchoolResults.growth(rows, year, subgroup)
    achievement_published? = SchoolResults.achievement_published?(performance)

    assigns =
      assign(assigns,
        performance: performance,
        growth: growth,
        achievement_published?: achievement_published?,
        achievement_latest:
          if(not achievement_published?,
            do: SchoolResults.latest_year_with(rows, :achievement, assigns.filters)
          ),
        growth_latest:
          if(growth == [], do: SchoolResults.latest_year_with(rows, :growth, assigns.filters)),
        engagement: SchoolResults.engagement(rows, year),
        survey_participation: SchoolResults.survey_participation(rows, year),
        type_label: type_label(type),
        subgroup_label: subgroup_label(subgroup),
        school_page:
          "https://insights.nd.gov/Education/School/StateAssessment/StudentAchievement/#{assigns.school.state_entity_id}",
        data_page: @insights_data,
        privacy_note: @privacy_note
      )

    ~H"""
    <section
      class="bg-base-100 border border-base-200 rounded-xl overflow-hidden scroll-mt-4"
      id="state-results"
    >
      <div class="px-4 py-3 border-b border-base-200 space-y-3">
        <div>
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="font-semibold">Official state results (ND Insights)</h2>
            <.link
              :if={@import_path}
              navigate={@import_path}
              class="btn btn-sm btn-outline"
              id="nd-import-link"
            >
              <.icon name="hero-arrow-up-tray" class="size-4" /> Import ND Insights data
            </.link>
          </div>
          <p class="text-sm text-base-content/60 mt-1">
            Annual results published by the state. They are separate from seasonal implementation
            ratings and are not assigned to a reporting period.
            <a href={@school_page} target="_blank" rel="noopener noreferrer" class="link link-primary">
              View on Insights
            </a>
            ·
            <a href={@data_page} target="_blank" rel="noopener noreferrer" class="link link-primary">
              Insights data downloads
            </a>
          </p>
        </div>

        <form
          :if={@state.years != []}
          phx-change="state_filters"
          id="state-filters"
          class="flex flex-wrap items-end gap-3"
        >
          <label class="form-control">
            <span class="label-text text-xs uppercase tracking-wide">Academic year</span>
            <span class="text-xs text-base-content/50">All sections</span>
            <select
              name="state_year"
              id="state_year"
              class="select select-bordered select-sm mt-1 w-40"
            >
              <option :for={y <- @state.years} value={y} selected={y == @filters.year}>{y}</option>
            </select>
          </label>
          <label class="form-control">
            <span class="label-text text-xs uppercase tracking-wide">Assessment type</span>
            <span class="text-xs text-base-content/50" id="state-type-scope">
              Achievement and % tested
            </span>
            <select
              name="state_type"
              id="state_type"
              class="select select-bordered select-sm mt-1 w-40"
            >
              <option
                :for={{code, label} <- SchoolResults.assessment_types()}
                value={code}
                selected={code == @filters.type}
              >
                {label}
              </option>
            </select>
          </label>
          <label class="form-control">
            <span class="label-text text-xs uppercase tracking-wide">Student group</span>
            <span class="text-xs text-base-content/50" id="state-subgroup-scope">
              Achievement and growth
            </span>
            <select
              name="state_subgroup"
              id="state_subgroup"
              class="select select-bordered select-sm mt-1 w-48"
              disabled={length(@filters.subgroups) < 2}
              aria-describedby={if length(@filters.subgroups) < 2, do: "state-subgroup-only"}
            >
              <option :for={s <- @filters.subgroups} value={s} selected={s == @filters.subgroup}>
                {subgroup_label(s)}
              </option>
            </select>
            <span
              :if={length(@filters.subgroups) < 2}
              class="text-xs text-base-content/50 mt-1"
              id="state-subgroup-only"
            >
              Only all students published for this year and assessment
            </span>
          </label>
          <label :if={@metrics != []} class="form-control">
            <span class="label-text text-xs uppercase tracking-wide">Compare with</span>
            <span class="text-xs text-base-content/50">Workbook goals (reference)</span>
            <select
              name="goal_ref"
              id="goal_ref"
              class="select select-bordered select-sm mt-1 w-44"
            >
              <option
                :for={{param, checkpoint, label} <- ResultGoals.references()}
                value={param}
                selected={checkpoint == @filters.reference}
              >
                {label}
              </option>
            </select>
          </label>
          <p class="text-xs text-base-content/50 basis-full">
            The Engagement Survey is shown for all students; the assessment type and student group
            filters do not apply to it.
          </p>
        </form>
      </div>

      <div
        :if={@state.years == []}
        class="text-center py-10 text-base-content/50"
        id="state-results-empty"
      >
        No official state results have been imported for this school.
      </div>

      <div :if={@state.years != []} class="divide-y divide-base-200">
        <.goal_legend reference={@filters.reference} config={@config} workbook?={@metrics != []} />

        <div class="p-4 space-y-2" id="state-achievement">
          <h3 class="font-medium">Achievement · {@filters.year}</h3>
          <p class="text-xs text-base-content/60" id="state-achievement-scope">
            {@type_label} assessment · {@subgroup_label}
          </p>
          <.section_notes
            id="achievement-goal-notes"
            notes={ResultGoals.section_notes(:achievement, @goals.achievement)}
          />
          <p
            :if={@config.section_notes[:achievement]}
            class="text-xs text-base-content/60"
            id="achievement-matching-note"
          >
            {@config.section_notes[:achievement]}
          </p>
          <p
            :if={
              @filters.type != "Comp" and @metrics != [] and
                @config.assumptions[:assessment_type] == "Comp"
            }
            class="text-xs text-base-content/60"
            id="achievement-type-note"
          >
            Workbook targets are compared only in the Combined assessment view (demo assumption).
          </p>
          <p
            :if={@filters.year not in @annual_goal_years}
            class="text-xs text-base-content/60"
            id="achievement-goal-years"
          >
            {ResultGoals.annual_years_note(@annual_goal_years, @filters.year)}<span :if={
              @metrics != []
            }> Workbook goals are compared with the selected reference target.</span>
          </p>
          <.scroll_hint />
          <div class="overflow-x-auto" tabindex="0" role="region" aria-label="Achievement table">
            <table class="table table-sm w-full">
              <thead>
                <tr class="bg-base-200/60 text-base-content/70 text-xs uppercase tracking-wide align-bottom">
                  <th>Subject</th>
                  <th>Grade</th>
                  <th
                    :for={{measure, label} <- SchoolResults.performance_levels()}
                    class="whitespace-normal"
                  >
                    {label}
                  </th>
                  <th class="whitespace-normal border-l border-base-200">
                    Proficient or Advanced
                    <span class="block normal-case tracking-normal">derived</span>
                  </th>
                  <th class="whitespace-normal border-l border-base-200">
                    Tested
                    <span class="block normal-case tracking-normal">assessment participation</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :if={not @achievement_published?}>
                  <td colspan="8" class="text-center text-base-content/50 italic">
                    <div class="font-medium not-italic text-base-content/70" id="achievement-empty">
                      No published achievement results for {@type_label} assessment · {@subgroup_label} · {@filters.year}.
                    </div>
                    <div class="text-xs">
                      The imported state download has no achievement rows for this combination.
                      <span :if={@performance != []} id="achievement-tested-only">
                        % tested is shown below where the participation download publishes it.
                      </span>
                      <span :if={@filters.type == "Alt" and is_nil(@achievement_latest)}>
                        Try Combined or Standard; Alternate-assessment results are published only for
                        groups the state reports.
                      </span>
                    </div>
                    <.latest_year_link
                      id="achievement-latest-year"
                      what="achievement"
                      year={@achievement_latest}
                      school={@school}
                      link_params={@link_params}
                    />
                  </td>
                </tr>
                <tr
                  :for={row <- @performance}
                  id={"achievement-#{slug(row.subject)}-#{slug(row.grade)}"}
                >
                  <td class="font-medium">{subject_label(row.subject)}</td>
                  <td>{row.grade}</td>
                  <td
                    :if={row.levels == %{}}
                    colspan="5"
                    class="text-center text-base-content/40 italic"
                    data-achievement="not-published"
                  >
                    Achievement not published
                  </td>
                  <td
                    :for={{measure, _} <- SchoolResults.performance_levels()}
                    :if={row.levels != %{}}
                    class={goal_class(goal(@goals, :achievement, row, measure))}
                  >
                    <.state_value result={row.levels[measure]} />
                    <.goal_mark m={goal(@goals, :achievement, row, measure)} />
                  </td>
                  <td
                    :if={row.levels != %{}}
                    class={[
                      "border-l border-base-200",
                      goal_class(goal(@goals, :achievement, row, :proficient_or_advanced))
                    ]}
                  >
                    <.derived value={row.proficient_or_advanced} />
                    <.goal_mark m={goal(@goals, :achievement, row, :proficient_or_advanced)} />
                  </td>
                  <td class="border-l border-base-200">
                    <.state_value result={row.tested} />
                    <.participation_mark c={cmp(@compared, :achievement, row, "PercentTested")} />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="text-xs text-base-content/60">
            “Approaching Proficiency” is the Insights website's label for the download column <span class="font-mono">Partially</span>. Proficient is shown alone; “Proficient or
            Advanced” is derived by adding the published Proficient and Advanced ranges and is
            unavailable when either is suppressed. Reading is shown as ELA. % tested is checked
            against the 95% participation target for ELA and math, Combined assessment, all
            students, All Grades: a participation target, not a school goal, so it doesn't
            color the cell.
          </p>
        </div>

        <div class="p-4 space-y-2" id="state-growth">
          <h3 class="font-medium">Growth · {@filters.year}</h3>
          <p class="text-xs text-base-content/60" id="state-growth-scope">
            {@subgroup_label} · the growth download has no assessment-type breakdown, so the
            assessment type filter does not apply
          </p>
          <.section_notes
            id="growth-goal-notes"
            notes={ResultGoals.section_notes(:growth, @goals.growth)}
          />
          <.scroll_hint />
          <div class="overflow-x-auto" tabindex="0" role="region" aria-label="Growth table">
            <table class="table table-sm w-full [&_td]:px-2 [&_th]:px-2" id="growth-table">
              <thead>
                <tr class="bg-base-200/60 text-base-content/70 text-xs uppercase tracking-wide align-bottom">
                  <th>Subject</th>
                  <th>Grade</th>
                  <th
                    :for={{measure, label} <- SchoolResults.growth_levels()}
                    class="whitespace-normal"
                  >
                    {label} growth expectation
                  </th>
                  <th class="whitespace-normal border-l border-base-200">
                    Meets or Exceeds <span class="block normal-case tracking-normal">derived</span>
                  </th>
                  <th class="whitespace-normal border-l border-base-200">Overall growth level</th>
                  <th class="whitespace-normal">Overall growth percentile</th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@growth == []}>
                  <td colspan="9" class="text-center text-base-content/50 italic">
                    <div class="font-medium not-italic text-base-content/70" id="growth-empty">
                      No published growth results for {@subgroup_label} · {@filters.year}.
                    </div>
                    <div class="text-xs">
                      The imported state growth download has no rows for this combination.
                    </div>
                    <.latest_year_link
                      id="growth-latest-year"
                      what="growth"
                      year={@growth_latest}
                      school={@school}
                      link_params={@link_params}
                    />
                  </td>
                </tr>
                <tr :for={row <- @growth} id={"growth-#{slug(row.subject)}-#{slug(row.grade)}"}>
                  <td class="font-medium">{subject_label(row.subject)}</td>
                  <td>{row.grade}</td>
                  <td :for={{measure, _} <- SchoolResults.growth_levels()}>
                    <.state_value result={row.levels[measure]} />
                  </td>
                  <td class="border-l border-base-200">
                    <.derived value={row.meets_or_exceeds} />
                  </td>
                  <td
                    :for={measure <- ~w(OverallGrowthLevel OverallGrowthPercentile)}
                    class={goal_class(goal(@goals, :growth, row, measure))}
                  >
                    <.state_value result={row.levels[measure]} />
                    <.goal_mark m={goal(@goals, :growth, row, measure)} />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="text-xs text-base-content/60" id="growth-matching-note">
            {@config.section_notes[:growth]} The category percentages are a distribution of students, not the
            school's classification, and have no matching goal; neither does the overall growth
            level, whose level numbers Insights doesn't define.
          </p>
        </div>

        <div class="p-4 space-y-2" id="state-engagement">
          <h3 class="font-medium">Student Engagement Survey · {@filters.year}</h3>
          <p class="text-xs text-base-content/60" id="state-engagement-scope">
            All students · the assessment type and student group filters do not apply
          </p>
          <.section_notes
            id="engagement-goal-notes"
            notes={ResultGoals.section_notes(:engagement, @goals.engagement)}
          />
          <.scroll_hint />
          <div class="overflow-x-auto" tabindex="0" role="region" aria-label="Engagement table">
            <table class="table table-sm w-full">
              <thead>
                <tr class="bg-base-200/60 text-base-content/70 text-xs uppercase tracking-wide">
                  <th>Engagement category</th>
                  <th :for={level <- ~w(Committed Compliant Disengaged)}>
                    {level}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@engagement == []}>
                  <td colspan="4" class="text-center text-base-content/50 italic">
                    <span id="engagement-empty">
                      No published Engagement Survey results for {@filters.year}.
                    </span>
                  </td>
                </tr>
                <tr :for={row <- @engagement} id={"engagement-#{row.area}"}>
                  <td class="font-medium">{row.label}</td>
                  <td
                    :for={level <- ~w(Committed Compliant Disengaged)}
                    class={goal_class(goal(@goals, :engagement, row, level))}
                  >
                    <.state_value result={row.levels[level]} />
                    <.goal_mark m={goal(@goals, :engagement, row, level)} />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <.survey_participation participation={@survey_participation} />

          <p
            :if={@config.section_notes[:engagement]}
            class="text-xs text-base-content/60"
            id="engagement-matching-note"
          >
            {@config.section_notes[:engagement]}
          </p>
        </div>

        <details class="p-4 group" id="nd-comparison">
          <summary class="cursor-pointer font-medium">
            North Dakota comparison
            <span class="text-xs font-normal text-base-content/60">
              · optional context, not a goal status
            </span>
          </summary>
          <div class="mt-2 space-y-2 text-xs text-base-content/70">
            <.nd_legend benchmark?={@compared.benchmark?} year={@filters.year} />
            <.coverage_note
              notes={StateComparison.coverage_notes(@compared, :achievement)}
              id="achievement-coverage"
              section="Achievement"
            />
            <.coverage_note
              notes={StateComparison.coverage_notes(@compared, :growth)}
              id="growth-coverage"
              section="Growth"
            />
            <.survey_benchmark
              :if={@engagement != []}
              note={StateComparison.survey_note(@compared.survey_benchmark)}
            />
            <p :if={@compared.benchmark?} id="state-benchmark-key">
              Every rated measure, with the matching statewide value (same year, subject, grade,
              assessment type and student group) and the reason for its color. Only lower Novice,
              Does not meet and Disengaged, and higher Advanced, Proficient or Advanced, Exceeds,
              Meets or Exceeds, Overall growth percentile and Committed are rated. This compares
              published values; it is not a goal result or a test of statistical significance.
            </p>
            <p :if={!@compared.benchmark?} id="state-benchmark-missing">
              No North Dakota benchmark rows have been imported for {@filters.year}. Importing an
              Insights file that includes the “State of North Dakota” rows adds them.
            </p>
            <div :if={@comparison_rows != []} class="overflow-x-auto">
              <table class="table table-xs w-full" id="nd-comparison-table">
                <thead>
                  <tr class="bg-base-200/60 text-base-content/70 uppercase tracking-wide">
                    <th>Section</th>
                    <th>Subject</th>
                    <th>Grade</th>
                    <th>Measure</th>
                    <th>This school</th>
                    <th>North Dakota</th>
                    <th>Comparison</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={r <- @comparison_rows} id={comparison_row_id(r)}>
                    <td>{section_label(r.section)}</td>
                    <td>{subject_label(r.subject)}</td>
                    <td>{r.grade}</td>
                    <td>{r.measure}</td>
                    <td class={["whitespace-nowrap", "nd-cell-#{r.tone}"]}>{r.school}</td>
                    <td class="whitespace-nowrap">{r.state || "—"}</td>
                    <td class={["min-w-64 whitespace-normal", "nd-cell-#{r.tone}"]}>
                      <span class={["font-medium", mark_text(r.tone)]}>
                        <span aria-hidden="true">{mark_symbol(r.tone)}</span> {r.label}
                      </span>
                      <span class="block text-base-content/70">{r.explanation}</span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <a
              :if={@compared.benchmark? and @comparison_pdf_path}
              href={@comparison_pdf_path}
              target="_blank"
              rel="noopener"
              class="link link-primary"
              id="nd-comparison-pdf"
            >
              Export PDF including the North Dakota comparison
            </a>
          </div>
        </details>

        <div class="p-4 text-xs text-base-content/60 space-y-2" id="state-sources">
          <div>
            “Not published” means the state's download has no row for that group. Insights notes:
            “{@privacy_note}”
          </div>
          <div>
            <button
              type="button"
              class="inline-flex items-center gap-1 font-medium text-base-content/70 hover:text-base-content"
              phx-click={
                JS.toggle(to: "#state-source-files")
                |> JS.toggle_class("rotate-90", to: "#state-source-files-chevron")
                |> JS.toggle_attribute({"aria-expanded", "true", "false"})
              }
              aria-expanded="false"
              aria-controls="state-source-files"
              id="state-source-files-toggle"
            >
              <span id="state-source-files-chevron" class="inline-flex transition-transform">
                <.icon name="hero-chevron-right-mini" class="size-4" />
              </span>
              Data sources ({length(@state.files)} files)
            </button>
            <ul id="state-source-files" class="hidden mt-1 pl-5 space-y-0.5">
              <li :for={file <- @state.files} class="font-mono break-all">
                {file.file_name} · version {file.publication_version} · sha256 {String.slice(
                  file.sha256,
                  0,
                  12
                )}…
              </li>
            </ul>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :participation, :any, required: true

  defp survey_participation(%{participation: nil} = assigns) do
    ~H"""
    <div class="text-sm" id="survey-participation">
      <span class="font-medium">Survey participation:</span>
      <span class="text-base-content/40 italic">Not published for this year</span>
    </div>
    """
  end

  defp survey_participation(%{participation: %{status: :consistent}} = assigns) do
    ~H"""
    <div class="text-sm space-y-0.5" id="survey-participation">
      <div>
        <span class="font-medium">Survey participation:</span>
        <.state_value result={@participation.result} />
        <span class="text-base-content/60">of enrolled students took the survey</span>
      </div>
      <div class="text-xs text-base-content/60">
        Insights shows this as “Overall Participation”. The download repeats it on its {Enum.map_join(
          @participation.rows,
          ", ",
          & &1.engagement_level
        )} rows
        ({length(@participation.rows)} source records, kept separately); they are identical
        for this year, so one value is shown.
      </div>
    </div>
    """
  end

  defp survey_participation(%{participation: %{status: :inconsistent}} = assigns) do
    ~H"""
    <div class="text-sm space-y-0.5" id="survey-participation">
      <div class="font-medium">Survey participation</div>
      <div class="text-xs text-base-content/60">
        The download's rows for this year disagree, so they are not combined:
      </div>
      <ul class="text-xs">
        <li :for={row <- @participation.rows}>
          {row.engagement_level} row: <.state_value result={row} />
        </li>
      </ul>
    </div>
    """
  end

  defp type_label(code) do
    case List.keyfind(SchoolResults.assessment_types(), code, 0) do
      {_, label} -> label
      nil -> code
    end
  end

  attr :id, :string, required: true
  attr :what, :string, required: true
  attr :year, :string, default: nil
  attr :school, :map, required: true
  attr :link_params, :map, required: true

  # A link to the latest academic year with matching imported results. It
  # changes only `state_year` (on click); the period, assessment type, student
  # group and reference checkpoint in the current URL are kept.
  defp latest_year_link(%{year: nil} = assigns) do
    ~H"""
    <div class="text-xs mt-1" id={@id} data-latest-year="none">
      No imported year has {@what} results for this combination.
    </div>
    """
  end

  defp latest_year_link(assigns) do
    query =
      assigns.link_params
      |> Map.put("state_year", assigns.year)
      |> Enum.reject(fn {_, v} -> v in [nil, ""] end)

    assigns = assign(assigns, path: ~p"/school-goals/#{assigns.school.slug}?#{query}")

    ~H"""
    <div class="text-xs not-italic mt-1" id={@id} data-latest-year={@year}>
      <.link patch={@path} class="link link-primary">
        View {@year}, the latest imported year with {@what} results
      </.link>
      for the same filters.
    </div>
    """
  end

  defp subgroup_label("All"), do: "All students"
  defp subgroup_label(subgroup), do: subgroup

  attr :result, :any, required: true

  def state_value(%{result: nil} = assigns) do
    ~H"""
    <span class="text-base-content/40 italic">Not published</span>
    """
  end

  def state_value(%{result: %{value_state: :suppressed}} = assigns) do
    ~H"""
    <span
      class="badge badge-ghost badge-sm"
      title={"Suppressed by the state (source cell “#{@result.source_text}”); not classified."}
    >
      Suppressed
    </span>
    """
  end

  def state_value(%{result: %{value_state: :exact}} = assigns) do
    ~H"""
    <span>{format(@result, @result.value)}</span>
    """
  end

  def state_value(%{result: %{value_state: :range}} = assigns) do
    ~H"""
    <span>{format(@result, @result.range_low)}–{format(@result, @result.range_high)}</span>
    """
  end

  attr :value, :any, required: true

  defp derived(%{value: {:ok, low, high}} = assigns) do
    assigns = assign(assigns, low: low, high: high)

    ~H"""
    <span>{interval(@low, @high)}</span>
    """
  end

  defp derived(%{value: {:not_derivable, reason}} = assigns) do
    assigns = assign(assigns, reason: reason)

    ~H"""
    <span class="text-base-content/50 italic" title={"A component is #{@reason}."}>
      Not derivable
    </span>
    """
  end

  defp interval(low, high) do
    if Decimal.equal?(low, high),
      do: Percent.format(low),
      else: "#{Percent.format(low)}–#{Percent.format(high)}"
  end

  defp format(%{unit: :proportion}, value), do: Percent.format(value)
  defp format(_result, value), do: Decimal.to_string(value, :normal)

  defp subject_label("Reading"), do: "ELA (Reading)"
  defp subject_label(subject), do: subject

  defp section_label(:achievement), do: "Achievement"
  defp section_label(:growth), do: "Growth"
  defp section_label(:engagement), do: "Engagement"

  defp comparison_row_id(r),
    do: "nd-row-#{r.section}-#{slug(r.subject)}-#{slug(r.grade)}-#{slug(r.measure)}"

  attr :reference, :atom, required: true
  attr :config, :map, required: true, doc: "`ResultGoals.config/1`"
  attr :workbook?, :boolean, default: true, doc: "false for a record with no workbook goals"

  defp goal_legend(assigns) do
    ~H"""
    <div class="px-4 pt-3 text-xs text-base-content/70 space-y-1.5" id="goal-legend">
      <p>{ResultGoals.legend_short()} Tap a status for its reason.</p>
      <p :if={@workbook?} class="font-medium text-base-content/80" id="goal-reference-note">
        {ResultGoals.reference_note(@reference)}
      </p>
      <ul class="flex flex-wrap gap-x-4 gap-y-1" aria-label="Goal status colors">
        <li :for={{tone, label} <- ResultGoals.legend_items()} id={"goal-legend-#{tone}"}>
          <span class={["nd-swatch", "nd-cell-#{tone}"]} aria-hidden="true"></span>
          <span class={["font-medium", goal_text(tone)]}>
            <span aria-hidden="true">{goal_symbol(tone)}</span> {label}
          </span>
        </li>
      </ul>
      <details id="goal-methodology">
        <summary class="cursor-pointer font-medium text-base-content/80">
          How results are matched to goals
        </summary>
        <ul class="mt-1 space-y-1">
          <li :for={text <- ResultGoals.methodology(@config)}>{text}</li>
        </ul>
      </details>
    </div>
    """
  end

  attr :benchmark?, :boolean, required: true
  attr :year, :string, required: true

  defp nd_legend(assigns) do
    ~H"""
    <div class="space-y-1.5" id="nd-color-legend">
      <p>{StateComparison.legend_short()}</p>
      <ul class="flex flex-wrap gap-x-4 gap-y-1" aria-label="Comparison colors">
        <li :for={{tone, label} <- StateComparison.legend_items()} id={"nd-legend-#{tone}"}>
          <span class={["nd-swatch", "nd-cell-#{tone}"]} aria-hidden="true"></span>
          <span class={["font-medium", mark_text(tone)]}>
            <span aria-hidden="true">{mark_symbol(tone)}</span> {label}
          </span>
        </li>
      </ul>
      <p :if={!@benchmark?} class="font-medium" id="nd-legend-no-benchmark">
        No North Dakota benchmark rows are imported for {@year}, so Achievement and Growth are not
        compared.
      </p>
      <details id="nd-methodology">
        <summary class="cursor-pointer font-medium text-base-content/80">
          How comparisons work (methodology and sources)
        </summary>
        <div class="mt-1 space-y-1">
          <p>{StateComparison.legend_intro()}</p>
          <p>{StateComparison.published_values_note()}</p>
          <p>
            Benchmark evidence, calculations and reproduction steps:
            <span class="font-mono">docs/nd_insights_benchmarks.md</span>
            in the project repository.
          </p>
        </div>
      </details>
    </div>
    """
  end

  attr :notes, :list, required: true
  attr :id, :string, required: true
  attr :section, :string, required: true

  # Why a section's All Grades rows are context only in the North Dakota comparison.
  defp coverage_note(%{notes: []} = assigns), do: ~H""

  defp coverage_note(assigns) do
    ~H"""
    <div class="text-xs text-base-content/70 rounded-md bg-base-200/60 px-3 py-2" id={@id}>
      <span class="font-medium text-base-content">
        {@section}: All Grades rows are gray (context only):
      </span>
      the grades they cover differ from North Dakota's, so they are different populations.
      <ul class="mt-0.5">
        <li :for={n <- @notes}>
          {subject_label(n.subject)}: this school {Enum.join(n.school_grades, ", ")} · North Dakota {Enum.join(
            n.state_grades,
            ", "
          )}
        </li>
      </ul>
      Grade rows are compared grade by grade.
    </div>
    """
  end

  attr :note, :map, required: true

  # Which Engagement benchmark applies this year, or exactly why none does.
  defp survey_benchmark(assigns) do
    ~H"""
    <div
      class={[
        "text-xs rounded-md px-3 py-2",
        if(@note.status == :compared,
          do: "bg-base-200/60 text-base-content/70",
          else: "nd-cell-warning text-base-content font-medium"
        )
      ]}
      id="engagement-benchmark"
      data-status={@note.status}
      role={if(@note.status == :not_compared, do: "note")}
    >
      <p>{@note.summary}</p>
      <details class="mt-1 font-normal" id="engagement-benchmark-details">
        <summary class="cursor-pointer">How this was checked</summary>
        <p class="mt-1">{@note.text}</p>
      </details>
    </div>
    """
  end

  # Wide tables scroll inside their card on narrow screens; say so there.
  defp scroll_hint(assigns) do
    ~H"""
    <p class="text-xs text-base-content/60 xl:hidden">
      Scroll the table sideways to see every column.
    </p>
    """
  end

  attr :notes, :list, required: true
  attr :id, :string, required: true

  # A section's goal-comparison notes, once above its table.
  defp section_notes(%{notes: []} = assigns), do: ~H""

  defp section_notes(assigns) do
    ~H"""
    <div class="text-xs font-medium text-base-content/80 space-y-0.5" id={@id}>
      <p :for={note <- @notes}>{note}</p>
    </div>
    """
  end

  attr :m, :any, required: true

  # A matching school goal under a value: its status (with the reason on tap
  # or keyboard), then the goal and its targets.
  defp goal_mark(%{m: nil} = assigns), do: ~H""

  defp goal_mark(assigns) do
    ~H"""
    <div
      class="mt-0.5 text-[11px] leading-tight"
      data-goal={@m.code || "annual"}
      data-kind={@m.kind}
      data-status={@m.status}
    >
      <details class="nd-mark">
        <summary class={["flex cursor-pointer gap-1 font-medium", goal_text(@m.tone)]}>
          <span aria-hidden="true" class="shrink-0">{goal_symbol(@m.tone)}</span>
          <span>{ResultGoals.short_label(@m)}</span>
        </summary>
        <p class="mt-1 w-56 whitespace-normal text-xs font-normal text-base-content/70">
          {ResultGoals.explanation(@m)}
        </p>
      </details>
      <div class="mt-0.5 text-base-content/70">{ResultGoals.goal_line(@m)}</div>
    </div>
    """
  end

  attr :c, :any, required: true

  # The 95% participation target under % tested: a labeled participation
  # check, never a goal status, so the cell itself isn't colored.
  # Shown only where the target applies (ELA and math, Combined, all
  # students, All Grades); the table note says so.
  defp participation_mark(%{c: %{reason: :target}} = assigns) do
    assigns = assign(assigns, tone: StateComparison.tone(assigns.c))

    ~H"""
    <details class="nd-mark mt-0.5" data-participation={@c.status}>
      <summary class={["flex cursor-pointer gap-1 text-[11px] leading-tight", mark_text(@tone)]}>
        <span aria-hidden="true" class="shrink-0">{mark_symbol(@tone)}</span>
        <span>{StateComparison.short_label(@c)}</span>
      </summary>
      <p class="mt-1 w-56 whitespace-normal text-xs text-base-content/70">
        {StateComparison.explanation(@c)}
      </p>
    </details>
    """
  end

  defp participation_mark(assigns), do: ~H""

  defp cmp(compared, section, row, measure),
    do: compared[section][{row.subject, row.grade}][measure]

  defp goal(goals, :engagement, row, measure), do: goals.engagement[row.area][measure]
  defp goal(goals, section, row, measure), do: goals[section][{row.subject, row.grade}][measure]

  defp goal_class(%{tone: tone}), do: "nd-cell-#{tone}"
  defp goal_class(_match), do: nil

  defp goal_text(tone) when tone in [:success, :error, :warning], do: "nd-text-#{tone}"
  defp goal_text(_muted), do: "text-base-content/70"

  defp goal_symbol(:success), do: "✓"
  defp goal_symbol(:error), do: "×"
  defp goal_symbol(:warning), do: "≈"
  defp goal_symbol(_muted), do: "–"

  defp mark_text(tone) when tone in [:success, :error, :warning], do: "nd-text-#{tone}"
  defp mark_text(:neutral), do: "text-base-content"
  defp mark_text(_muted), do: "text-base-content/60"

  defp mark_symbol(:success), do: "✓"
  defp mark_symbol(:error), do: "×"
  defp mark_symbol(:warning), do: "≈"
  defp mark_symbol(:neutral), do: "="
  defp mark_symbol(_muted), do: "–"

  defp slug(nil), do: "none"
  defp slug(text), do: text |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
end
