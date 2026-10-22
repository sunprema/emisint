defmodule EmisintWeb.Improvement.StateResultsComponents do
  @moduledoc """
  Official ND Insights results for a school: achievement (with Proficient
  alone and the derived Proficient-or-Advanced range shown separately),
  participation, growth and the Engagement Survey, plus source files.

  Values are shown as published: exact, a range (never a midpoint) or
  "Suppressed". A group the state did not publish is "Not published".
  These are annual results and are never tied to a seasonal period.
  """
  use EmisintWeb, :html

  alias Emisint.Improvement.Percent
  alias Emisint.NdInsights.SchoolResults

  @insights_data "https://insights.nd.gov/Data"
  @privacy_note "To protect student privacy, data for populations with less than 10 students will not be displayed."

  attr :comparison, :map, required: true

  def goal_comparison(%{comparison: %{status: :not_published}} = assigns) do
    ~H"""
    <span class="text-base-content/50 italic">Not yet published</span>
    """
  end

  def goal_comparison(%{comparison: %{status: :not_derivable}} = assigns) do
    ~H"""
    <span class="badge badge-ghost badge-sm">Not derivable</span>
    <div class="text-xs text-base-content/60">Proficient or Advanced is {@comparison.reason}.</div>
    """
  end

  def goal_comparison(%{comparison: %{status: status}} = assigns)
      when status in [:meets, :below, :pending_range_clarification] do
    ~H"""
    <span class="font-semibold">{interval(@comparison.low, @comparison.high)}</span>
    <span class="badge badge-outline badge-xs ml-1">Derived</span>
    <span class={["badge badge-sm ml-1", status_badge(@comparison.status)]}>
      {status_label(@comparison.status)}
    </span>
    <div class="text-xs text-base-content/60">
      Derived by adding the published Proficient and Advanced values · {@comparison.match.assessment_type} · {@comparison.match.grade} · {@comparison.match.subgroup}
    </div>
    <div :if={@comparison.status == :pending_range_clarification} class="text-xs text-base-content/60">
      No verdict: the state publishes these values as ranges and has not documented what a range's
      endpoints mean (for example, whether 29% means “up to 29%” or “below 30%”).
    </div>
    <div :if={@comparison.status in [:meets, :below]} class="text-xs text-base-content/60">
      Both components were published as exact values and are compared as published.
    </div>
    """
  end

  def goal_comparison(assigns) do
    ~H"""
    <span class="text-base-content/40">—</span>
    """
  end

  attr :school, :map, required: true
  attr :state, :map, required: true
  attr :filters, :map, required: true
  attr :annual_goal_years, :list, required: true

  def state_results(assigns) do
    %{rows: rows} = assigns.state
    %{year: year, type: type, subgroup: subgroup} = assigns.filters

    assigns =
      assign(assigns,
        performance: SchoolResults.performance(rows, year, type, subgroup),
        growth: SchoolResults.growth(rows, year, subgroup),
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
          <h2 class="font-semibold">Official state results (ND Insights)</h2>
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
            >
              <option :for={s <- @filters.subgroups} value={s} selected={s == @filters.subgroup}>
                {subgroup_label(s)}
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
        <div class="p-4 space-y-2" id="state-achievement">
          <h3 class="font-medium">Achievement · {@filters.year}</h3>
          <p class="text-xs text-base-content/60" id="state-achievement-scope">
            {@type_label} assessment · {@subgroup_label}
          </p>
          <p :if={@filters.year not in @annual_goal_years} class="text-xs text-base-content/60">
            The school's annual goals start in 2025-2026; earlier years are shown for context only.
          </p>
          <div class="overflow-x-auto">
            <table class="table table-sm w-full">
              <thead>
                <tr class="bg-base-200/60 text-base-content/70 text-xs uppercase tracking-wide align-bottom">
                  <th>Subject</th>
                  <th>Grade</th>
                  <th
                    :for={{_, label} <- SchoolResults.performance_levels()}
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
                <tr :if={@performance == []}>
                  <td colspan="8" class="text-center text-base-content/50 italic">
                    Not published for this year, assessment and student group.
                  </td>
                </tr>
                <tr
                  :for={row <- @performance}
                  id={"achievement-#{slug(row.subject)}-#{slug(row.grade)}"}
                >
                  <td class="font-medium">{subject_label(row.subject)}</td>
                  <td>{row.grade}</td>
                  <td :for={{measure, _} <- SchoolResults.performance_levels()}>
                    <.state_value result={row.levels[measure]} />
                  </td>
                  <td class="border-l border-base-200">
                    <.derived value={row.proficient_or_advanced} />
                  </td>
                  <td class="border-l border-base-200"><.state_value result={row.tested} /></td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="text-xs text-base-content/60">
            “Approaching Proficiency” is the Insights website's label for the download column <span class="font-mono">Partially</span>. Proficient is shown alone; “Proficient or
            Advanced” is derived by adding the published Proficient and Advanced ranges and is
            unavailable when either is suppressed. Reading is shown as ELA.
          </p>
        </div>

        <div class="p-4 space-y-2" id="state-growth">
          <h3 class="font-medium">Growth · {@filters.year}</h3>
          <p class="text-xs text-base-content/60" id="state-growth-scope">
            {@subgroup_label} · the growth download has no assessment-type breakdown, so the
            assessment type filter does not apply
          </p>
          <div class="overflow-x-auto">
            <table class="table table-sm w-full">
              <thead>
                <tr class="bg-base-200/60 text-base-content/70 text-xs uppercase tracking-wide align-bottom">
                  <th>Subject</th>
                  <th>Grade</th>
                  <th :for={{_, label} <- SchoolResults.growth_levels()} class="whitespace-normal">
                    {label} growth expectation
                  </th>
                  <th class="whitespace-normal border-l border-base-200">Overall growth level</th>
                  <th class="whitespace-normal">Overall growth percentile</th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@growth == []}>
                  <td colspan="8" class="text-center text-base-content/50 italic">
                    Not published for this year and student group.
                  </td>
                </tr>
                <tr :for={row <- @growth} id={"growth-#{slug(row.subject)}-#{slug(row.grade)}"}>
                  <td class="font-medium">{subject_label(row.subject)}</td>
                  <td>{row.grade}</td>
                  <td :for={{measure, _} <- SchoolResults.growth_levels()}>
                    <.state_value result={row.levels[measure]} />
                  </td>
                  <td class="border-l border-base-200">
                    <.state_value result={row.levels["OverallGrowthLevel"]} />
                  </td>
                  <td><.state_value result={row.levels["OverallGrowthPercentile"]} /></td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="text-xs text-base-content/60">
            Not compared with the workbook's growth metrics: the workbook does not say which
            growth categories, years or grades its “met state growth expectations” measure uses.
          </p>
        </div>

        <div class="p-4 space-y-2" id="state-engagement">
          <h3 class="font-medium">Student Engagement Survey · {@filters.year}</h3>
          <p class="text-xs text-base-content/60" id="state-engagement-scope">
            All students · the assessment type and student group filters do not apply
          </p>
          <div class="overflow-x-auto">
            <table class="table table-sm w-full">
              <thead>
                <tr class="bg-base-200/60 text-base-content/70 text-xs uppercase tracking-wide">
                  <th>Engagement category</th>
                  <th>Committed</th>
                  <th>Compliant</th>
                  <th>Disengaged</th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@engagement == []}>
                  <td colspan="4" class="text-center text-base-content/50 italic">
                    Not published for this year.
                  </td>
                </tr>
                <tr :for={row <- @engagement} id={"engagement-#{row.area}"}>
                  <td class="font-medium">{row.label}</td>
                  <td :for={level <- ~w(Committed Compliant Disengaged)}>
                    <.state_value result={row.levels[level]} />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <.survey_participation participation={@survey_participation} />

          <p class="text-xs text-base-content/60">
            Not compared with the workbook's disengagement metrics automatically: their baseline
            year and survey grades are not stated in the workbook.
          </p>
        </div>

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
    <span class="badge badge-warning badge-sm" title={"Source cell: “#{@result.source_text}”"}>
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

  defp status_label(:meets), do: "Meets goal"
  defp status_label(:below), do: "Below goal"
  defp status_label(:pending_range_clarification), do: "Goal status pending range clarification"

  defp status_badge(:meets), do: "badge-success"
  defp status_badge(:below), do: "badge-error"
  defp status_badge(:pending_range_clarification), do: "badge-ghost"

  defp slug(nil), do: "none"
  defp slug(text), do: text |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
end
