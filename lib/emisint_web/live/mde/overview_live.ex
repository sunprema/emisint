defmodule EmisintWeb.Mde.OverviewLive do
  use EmisintWeb, :live_view

  require Ash.Query

  alias Emisint.Assessments.MdeStateAssessmentResult

  @subjects ["ELA", "Mathematics", "Science", "Social Studies"]

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  def mount(_params, _session, socket) do
    years = load_school_years()
    selected_year = List.last(years)

    {stats, district_rows} =
      if selected_year, do: load_data(selected_year), else: {nil, []}

    {:ok,
     socket
     |> assign(:page_title, "MDE State Assessments")
     |> assign(:school_years, years)
     |> assign(:selected_year, selected_year)
     |> assign(:stats, stats)
     |> assign(:district_rows, district_rows)}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  def handle_event("select_year", %{"year" => year}, socket) do
    {stats, district_rows} = load_data(year)

    {:noreply,
     socket
     |> assign(:selected_year, year)
     |> assign(:stats, stats)
     |> assign(:district_rows, district_rows)}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  def render(assigns) do
    assigns = assign(assigns, :subjects, @subjects)

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-6xl mx-auto space-y-8">

        <%!-- Header + year selector --%>
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div class="flex items-center gap-4">
            <div class="p-2.5 bg-info/10 border border-info/20">
              <.icon name="hero-chart-bar-square" class="size-6 text-info" />
            </div>
            <div>
              <h1 class="text-2xl font-bold tracking-tight">MDE State Assessments</h1>
              <p class="text-sm text-base-content/50 mt-0.5">
                Michigan statewide M-STEP, PSAT, and SAT public results
              </p>
            </div>
          </div>

          <div :if={@school_years != []} class="flex items-center gap-2 shrink-0">
            <label class="text-sm font-medium text-base-content/60">School Year</label>
            <select
              name="year"
              phx-change="select_year"
              class="border border-base-300 bg-base-100 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-info/25 focus:border-info transition-all"
            >
              <option :for={year <- @school_years} value={year} selected={year == @selected_year}>
                {year}
              </option>
            </select>
          </div>
        </div>

        <%!-- Empty state — no data imported yet --%>
        <div
          :if={@school_years == []}
          class="bg-base-100 border border-base-200 flex flex-col items-center justify-center py-24 text-center"
        >
          <div class="p-4 bg-base-200 mb-4">
            <.icon name="hero-chart-bar-square" class="size-10 text-base-content/20" />
          </div>
          <p class="text-base font-semibold text-base-content/50">No MDE data imported yet</p>
          <p class="text-sm text-base-content/35 mt-1 max-w-xs">
            Upload a Michigan MDE assessment CSV export from the Data Import page to populate this view.
          </p>
          <.link
            navigate={~p"/admin/import"}
            class="mt-4 inline-flex items-center gap-1.5 text-sm text-info font-medium hover:underline"
          >
            Go to Data Import <.icon name="hero-arrow-right" class="size-4" />
          </.link>
        </div>

        <%!-- ── Summary stat cards ────────────────────────────────────────────── --%>
        <div :if={@stats} class="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <.stat_card
            label="Buildings"
            value={format_number(@stats.buildings)}
            icon="hero-building-office-2"
            color="info"
          />
          <.stat_card
            label="Districts"
            value={format_number(@stats.districts)}
            icon="hero-map"
            color="info"
          />
          <.stat_card
            label="ISDs"
            value={format_number(@stats.isds)}
            icon="hero-globe-americas"
            color="info"
          />
          <.stat_card
            label="Students Assessed"
            value={format_number(@stats.students_assessed)}
            icon="hero-users"
            color="info"
          />
        </div>

        <%!-- ── M-STEP Proficiency by Subject ────────────────────────────────── --%>
        <div :if={@stats} class="space-y-3">
          <div class="flex items-center gap-2">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
              M-STEP Proficiency — All Students, Statewide
            </h2>
            <div class="flex-1 h-px bg-base-200"></div>
          </div>

          <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <.subject_card
              :for={subject <- @subjects}
              subject={subject}
              proficiency={Map.get(@stats.proficiency_by_subject, subject)}
            />
          </div>
        </div>

        <%!-- ── Test Type Coverage ─────────────────────────────────────────────── --%>
        <div :if={@stats && map_size(@stats.by_test_type) > 0} class="space-y-3">
          <div class="flex items-center gap-2">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
              Assessment Coverage
            </h2>
            <div class="flex-1 h-px bg-base-200"></div>
          </div>

          <div class="flex flex-wrap gap-3">
            <div
              :for={{test_type, info} <- Enum.sort(@stats.by_test_type)}
              class="flex items-center gap-3 px-4 py-3 bg-base-100 border border-base-200"
            >
              <div>
                <div class="text-sm font-semibold">{test_type}</div>
                <div class="text-xs text-base-content/45 mt-0.5">
                  {format_number(info.buildings)} buildings · {format_number(info.records)} rows
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- ── District Breakdown Table ────────────────────────────────────────── --%>
        <div :if={@district_rows != []} class="space-y-3">
          <div class="flex items-center gap-2">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
              District Breakdown — M-STEP All Students
            </h2>
            <div class="flex-1 h-px bg-base-200"></div>
            <span class="text-xs text-base-content/35">
              {length(@district_rows)} districts · sorted by ELA proficiency
            </span>
          </div>

          <div class="bg-base-100 border border-base-200 overflow-hidden">
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b border-base-200 bg-base-50">
                    <th class="text-left px-4 py-3 font-medium text-base-content/60 text-xs uppercase tracking-wide">
                      District
                    </th>
                    <th class="text-left px-4 py-3 font-medium text-base-content/60 text-xs uppercase tracking-wide hidden sm:table-cell">
                      Type
                    </th>
                    <th class="text-center px-4 py-3 font-medium text-base-content/60 text-xs uppercase tracking-wide hidden md:table-cell">
                      Buildings
                    </th>
                    <th class="text-right px-4 py-3 font-medium text-base-content/60 text-xs uppercase tracking-wide">
                      ELA %
                    </th>
                    <th class="text-right px-4 py-3 font-medium text-base-content/60 text-xs uppercase tracking-wide">
                      Math %
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-base-200">
                  <tr
                    :for={row <- @district_rows}
                    class="hover:bg-base-50 transition-colors"
                  >
                    <td class="px-4 py-3 font-medium">{row.district_name}</td>
                    <td class="px-4 py-3 text-xs text-base-content/50 hidden sm:table-cell">
                      {row.entity_type || "—"}
                    </td>
                    <td class="px-4 py-3 text-center text-base-content/50 hidden md:table-cell">
                      {row.buildings}
                    </td>
                    <td class="px-4 py-3 text-right">
                      <.pct_badge value={row.ela} />
                    </td>
                    <td class="px-4 py-3 text-right">
                      <.pct_badge value={row.math} />
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :color, :string, default: "primary"

  def stat_card(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-200 p-5">
      <div class="flex items-center justify-between mb-3">
        <span class="text-xs font-medium text-base-content/40 uppercase tracking-wider">
          {@label}
        </span>
        <div class={"p-1.5 bg-#{@color}/10"}>
          <.icon name={@icon} class={"size-4 text-#{@color}"} />
        </div>
      </div>
      <div class="text-3xl font-bold tracking-tight tabular-nums">{@value}</div>
    </div>
    """
  end

  attr :subject, :string, required: true
  attr :proficiency, :any, default: nil

  def subject_card(assigns) do
    pct_float =
      case assigns.proficiency do
        nil -> nil
        d -> Decimal.to_float(d)
      end

    color =
      cond do
        is_nil(pct_float) -> "base-content/20"
        pct_float >= 50.0 -> "success"
        pct_float >= 35.0 -> "warning"
        true -> "error"
      end

    assigns = assigns |> assign(:pct_float, pct_float) |> assign(:color, color)

    ~H"""
    <div class="bg-base-100 border border-base-200 p-5 space-y-3">
      <div class="text-xs font-medium text-base-content/50 uppercase tracking-wide">
        {@subject}
      </div>

      <div class={"text-3xl font-bold tracking-tight tabular-nums text-#{@color}"}>
        {if @proficiency, do: "#{@proficiency}%", else: "—"}
      </div>

      <%!-- Proficiency bar --%>
      <div class="w-full bg-base-200 h-1.5">
        <div
          class={"h-1.5 bg-#{@color} transition-all duration-500"}
          style={"width: #{if @pct_float, do: min(@pct_float, 100), else: 0}%"}
        >
        </div>
      </div>

      <div class="text-xs text-base-content/35">
        {proficiency_label(@pct_float)}
      </div>
    </div>
    """
  end

  attr :value, :any, default: nil

  def pct_badge(assigns) do
    color =
      case assigns.value do
        nil ->
          "base-content/30"

        d ->
          f = Decimal.to_float(d)
          cond do
            f >= 50.0 -> "success"
            f >= 35.0 -> "warning"
            true -> "error"
          end
      end

    assigns = assign(assigns, :color, color)

    ~H"""
    <span class={"font-semibold tabular-nums text-#{@color}"}>
      {if @value, do: "#{@value}%", else: "—"}
    </span>
    """
  end

  # ---------------------------------------------------------------------------
  # Data loading
  # ---------------------------------------------------------------------------

  defp load_school_years do
    MdeStateAssessmentResult
    |> Ash.Query.select([:school_year])
    |> Ash.Query.sort(:school_year)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.school_year)
    |> Enum.uniq()
  end

  defp load_data(year) do
    # One query: all "All Students" rows for the year, with building → district loaded
    results =
      MdeStateAssessmentResult
      |> Ash.Query.filter(school_year == ^year and report_category == "All Students")
      |> Ash.Query.load(mde_building: :mde_district)
      |> Ash.read!(authorize?: false)

    mstep = Enum.filter(results, &(&1.test_type == "M-STEP"))

    # ── Summary stats ──────────────────────────────────────────────────────

    buildings_count =
      results |> Enum.map(& &1.mde_building_id) |> Enum.uniq() |> length()

    districts_count =
      results
      |> Enum.map(fn r -> r.mde_building && r.mde_building.mde_district_id end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> length()

    isds_count =
      results
      |> Enum.map(fn r ->
        r.mde_building && r.mde_building.mde_district &&
          r.mde_building.mde_district.mde_isd_id
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> length()

    # ELA as proxy for student count (avoids double-counting across subjects)
    students_assessed =
      mstep
      |> Enum.filter(&(&1.subject == "ELA"))
      |> Enum.map(&(&1.number_assessed || 0))
      |> Enum.sum()

    # ── M-STEP proficiency by subject ──────────────────────────────────────

    proficiency_by_subject =
      Map.new(@subjects, fn subject ->
        rows = Enum.filter(mstep, &(&1.subject == subject))
        {subject, weighted_proficiency(rows)}
      end)

    # ── Assessment coverage by test type ──────────────────────────────────

    by_test_type =
      results
      |> Enum.group_by(& &1.test_type)
      |> Map.new(fn {type, rows} ->
        buildings = rows |> Enum.map(& &1.mde_building_id) |> Enum.uniq() |> length()
        {type, %{buildings: buildings, records: length(rows)}}
      end)

    # ── District breakdown (ELA + Math, sorted by ELA desc) ───────────────

    district_rows =
      mstep
      |> Enum.filter(&(&1.subject in ["ELA", "Mathematics"]))
      |> Enum.group_by(fn r -> r.mde_building && r.mde_building.mde_district end)
      |> Enum.reject(fn {district, _} -> is_nil(district) end)
      |> Enum.map(fn {district, rows} ->
        ela_rows = Enum.filter(rows, &(&1.subject == "ELA"))
        math_rows = Enum.filter(rows, &(&1.subject == "Mathematics"))
        buildings = rows |> Enum.map(& &1.mde_building_id) |> Enum.uniq() |> length()

        %{
          district_name: district.district_name,
          entity_type: district.entity_type,
          buildings: buildings,
          ela: weighted_proficiency(ela_rows),
          math: weighted_proficiency(math_rows)
        }
      end)
      |> Enum.sort_by(
        fn row ->
          case row.ela do
            nil -> -1.0
            d -> Decimal.to_float(d)
          end
        end,
        :desc
      )

    stats = %{
      buildings: buildings_count,
      districts: districts_count,
      isds: isds_count,
      students_assessed: students_assessed,
      proficiency_by_subject: proficiency_by_subject,
      by_test_type: by_test_type
    }

    {stats, district_rows}
  end

  # Weighted proficiency = (Σ advanced + Σ proficient) / Σ number_assessed × 100
  # Returns nil when there are no assessed students (suppressed data)
  defp weighted_proficiency([]), do: nil

  defp weighted_proficiency(rows) do
    {total_assessed, total_prof} =
      Enum.reduce(rows, {0, 0}, fn r, {assessed, prof} ->
        {
          assessed + (r.number_assessed || 0),
          prof + (r.total_advanced || 0) + (r.total_proficient || 0)
        }
      end)

    if total_assessed > 0 do
      total_prof
      |> Decimal.new()
      |> Decimal.div(Decimal.new(total_assessed))
      |> Decimal.mult(Decimal.new(100))
      |> Decimal.round(1)
    else
      nil
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp proficiency_label(nil), do: "No data"
  defp proficiency_label(f) when f >= 50.0, do: "Above state threshold"
  defp proficiency_label(f) when f >= 35.0, do: "Approaching threshold"
  defp proficiency_label(_), do: "Below threshold"

  defp format_number(nil), do: "—"
  defp format_number(0), do: "0"

  defp format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.join()
  end
end
