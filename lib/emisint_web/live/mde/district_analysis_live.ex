defmodule EmisintWeb.Mde.DistrictAnalysisLive do
  use EmisintWeb, :live_view

  require Ash.Query

  alias Emisint.Assessments.{
    MdeBuilding,
    MdeDistrict,
    MdeDistrictSnapshot,
    MdeSchoolVsLeaSnapshot,
    MdeStateAssessmentResult
  }

  @subjects ["ELA", "Mathematics", "Science", "Social Studies"]

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  def mount(_params, _session, socket) do
    years = load_school_years()
    selected_year = List.last(years) || ""
    all_districts = load_all_districts()

    {:ok,
     socket
     |> assign(:page_title, "District Analysis")
     |> assign(:school_years, years)
     |> assign(:selected_year, selected_year)
     |> assign(:all_districts, all_districts)
     |> assign(:district_code, nil)
     |> assign(:compare_code, "")
     |> assign(:primary, nil)
     |> assign(:compare, nil)
     |> assign(:active_tab, "school_vs_lea")
     |> assign(:district_buildings, [])
     |> assign(:selected_building_code, nil)
     |> assign(:school_vs_lea, nil)}
  end

  def handle_params(%{"district_code" => dc} = params, _uri, socket) do
    tab = Map.get(params, "tab", "school_vs_lea")
    building_code = Map.get(params, "building", nil)
    year = socket.assigns.selected_year
    compare_code = Map.get(params, "compare", "")

    {primary, compare} =
      if tab == "district_comparison" do
        p = if year != "", do: load_district_data(dc, year), else: nil

        c =
          if compare_code != "" && year != "",
            do: load_district_data(compare_code, year),
            else: nil

        {p, c}
      else
        {socket.assigns.primary, socket.assigns.compare}
      end

    district_buildings =
      if tab == "school_vs_lea", do: load_district_buildings(dc), else: []

    # Auto-select building: use URL param first, fall back to sole building in district
    effective_building_code =
      building_code ||
        case district_buildings do
          [sole] -> sole.building_code
          _ -> nil
        end

    school_vs_lea =
      if tab == "school_vs_lea" && effective_building_code && year != "" do
        load_school_vs_lea(effective_building_code, year)
      else
        nil
      end

    {:noreply,
     socket
     |> assign(:district_code, dc)
     |> assign(:compare_code, compare_code)
     |> assign(:active_tab, tab)
     |> assign(:primary, primary)
     |> assign(:compare, compare)
     |> assign(:district_buildings, district_buildings)
     |> assign(:selected_building_code, effective_building_code)
     |> assign(:school_vs_lea, school_vs_lea)
     |> assign(:page_title, page_title(primary, compare))}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  def handle_event("select_year", %{"year" => year}, socket) do
    dc = socket.assigns.district_code
    tab = socket.assigns.active_tab
    building_code = socket.assigns.selected_building_code

    {primary, compare} =
      if tab == "district_comparison" do
        p = if dc, do: load_district_data(dc, year), else: nil

        c =
          if socket.assigns.compare_code != "",
            do: load_district_data(socket.assigns.compare_code, year),
            else: nil

        {p, c}
      else
        {socket.assigns.primary, socket.assigns.compare}
      end

    # Honor auto-selected sole building the same way handle_params does
    effective_building_code =
      building_code ||
        case socket.assigns.district_buildings do
          [sole] -> sole.building_code
          _ -> nil
        end

    school_vs_lea =
      if tab == "school_vs_lea" && effective_building_code && year != "" do
        load_school_vs_lea(effective_building_code, year)
      else
        socket.assigns.school_vs_lea
      end

    {:noreply,
     socket
     |> assign(:selected_year, year)
     |> assign(:primary, primary)
     |> assign(:compare, compare)
     |> assign(:school_vs_lea, school_vs_lea)}
  end

  def handle_event("select_compare", %{"compare" => ""}, socket) do
    {:noreply, push_patch(socket, to: ~p"/mde/districts/#{socket.assigns.district_code}")}
  end

  def handle_event("select_compare", %{"compare" => code}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/mde/districts/#{socket.assigns.district_code}?compare=#{code}&tab=district_comparison"
     )}
  end

  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/mde/districts/#{socket.assigns.district_code}?tab=#{tab}")}
  end

  def handle_event("select_building", %{"building" => ""}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/mde/districts/#{socket.assigns.district_code}?tab=school_vs_lea"
     )}
  end

  def handle_event("select_building", %{"building" => code}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/mde/districts/#{socket.assigns.district_code}?tab=school_vs_lea&building=#{code}"
     )}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  def render(assigns) do
    assigns = assign(assigns, :subjects, @subjects)

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-6xl mx-auto space-y-8">
        <%!-- Top bar: back link + year selector --%>
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div class="flex items-center gap-4">
            <.link
              navigate={~p"/mde"}
              class="flex items-center gap-1.5 text-sm text-base-content/50 hover:text-base-content transition-colors"
            >
              <.icon name="hero-arrow-left" class="size-4" /> MDE Overview
            </.link>
            <div class="h-4 w-px bg-base-300"></div>
            <div class="flex items-center gap-2">
              <div class="p-1.5 bg-info/10 border border-info/20">
                <.icon name="hero-chart-bar" class="size-4 text-info" />
              </div>
              <h1 class="text-lg font-bold tracking-tight">District Analysis</h1>
            </div>
          </div>

          <div :if={@school_years != []} class="flex items-center gap-2 shrink-0">
            <label class="text-sm font-medium text-base-content/60">School Year</label>
            <form>
              <select
                name="year"
                phx-change="select_year"
                class="border border-base-300 bg-base-100 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-info/25 focus:border-info transition-all"
              >
                <option
                  :for={year <- @school_years}
                  value={year}
                  selected={year == @selected_year}
                >
                  {year}
                </option>
              </select>
            </form>
          </div>
        </div>

        <%!-- Tab bar --%>
        <div class="flex border-b border-base-200">
          <button
            phx-click="select_tab"
            phx-value-tab="school_vs_lea"
            class={tab_class(@active_tab == "school_vs_lea")}
          >
            School vs Geographic LEA
          </button>
          <button
            phx-click="select_tab"
            phx-value-tab="district_comparison"
            class={tab_class(@active_tab == "district_comparison")}
          >
            District Comparison
          </button>
        </div>

        <%!-- ══ Tab 2: District Comparison ══════════════════════════════════════ --%>
        <div :if={@active_tab == "district_comparison"} class="space-y-8">
          <%!-- District headers --%>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <%!-- Primary district --%>
            <.district_header district={@primary} label="Primary District" color="info" />

            <%!-- Compare district --%>
            <div class="bg-base-100 border border-base-200 p-5 space-y-3">
              <div class="text-xs font-semibold uppercase tracking-wider text-base-content/40">
                Comparison District
              </div>
              <form phx-change="select_compare">
                <select
                  name="compare"
                  class="w-full border border-base-300 bg-base-100 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-warning/25 focus:border-warning transition-all"
                >
                  <option value="">— Select a district to compare —</option>
                  <option
                    :for={d <- @all_districts}
                    value={d.district_code}
                    selected={d.district_code == @compare_code}
                  >
                    {d.district_name} ({d.entity_type || "—"})
                  </option>
                </select>
              </form>
              <.district_header :if={@compare} district={@compare} label="District" color="warning" />
              <div
                :if={!@compare}
                class="text-sm text-base-content/35 text-center py-4 border border-dashed border-base-300"
              >
                Select a district above to compare side-by-side
              </div>
            </div>
          </div>

          <%!-- ── Subject Proficiency Side-by-Side ──────────────────────────────── --%>
          <div :if={@primary} class="space-y-3">
            <div class="flex items-center gap-2">
              <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
                M-STEP Proficiency by Subject
              </h2>
              <div class="flex-1 h-px bg-base-200"></div>
            </div>

            <div class="bg-base-100 border border-base-200 p-5 space-y-5">
              <.subject_comparison
                :for={subject <- @subjects}
                subject={subject}
                primary={Map.get(@primary.all_subjects, subject)}
                primary_label={short_name(@primary.district_name)}
                compare={@compare && Map.get(@compare.all_subjects, subject)}
                compare_label={@compare && short_name(@compare.district_name)}
              />
            </div>
          </div>

          <%!-- ── Grade Breakdown ─────────────────────────────────────────────────── --%>
          <div :if={@primary && @primary.grade_breakdown != []} class="space-y-3">
            <div class="flex items-center gap-2">
              <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
                Grade-Level Breakdown — ELA &amp; Math
              </h2>
              <div class="flex-1 h-px bg-base-200"></div>
            </div>

            <div class="bg-base-100 border border-base-200 overflow-hidden">
              <div class="overflow-x-auto">
                <table class="w-full text-sm">
                  <thead>
                    <tr class="border-b border-base-200 bg-base-50">
                      <th class="text-left px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                        Grade
                      </th>
                      <th class="text-right px-4 py-3 text-xs font-medium text-info uppercase tracking-wide">
                        ELA — {short_name(@primary.district_name)}
                      </th>
                      <th
                        :if={@compare}
                        class="text-right px-4 py-3 text-xs font-medium text-warning uppercase tracking-wide"
                      >
                        ELA — {short_name(@compare.district_name)}
                      </th>
                      <th class="text-right px-4 py-3 text-xs font-medium text-info uppercase tracking-wide">
                        Math — {short_name(@primary.district_name)}
                      </th>
                      <th
                        :if={@compare}
                        class="text-right px-4 py-3 text-xs font-medium text-warning uppercase tracking-wide"
                      >
                        Math — {short_name(@compare.district_name)}
                      </th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-base-200">
                    <tr
                      :for={
                        grade_row <-
                          align_grades(@primary.grade_breakdown, @compare && @compare.grade_breakdown)
                      }
                      class="hover:bg-base-50"
                    >
                      <td class="px-4 py-2.5 font-medium text-xs">{grade_label(grade_row.grade)}</td>
                      <td class="px-4 py-2.5 text-right">
                        <.pct_badge value={grade_row.primary_ela} color="info" />
                      </td>
                      <td :if={@compare} class="px-4 py-2.5 text-right">
                        <.pct_badge value={grade_row.compare_ela} color="warning" />
                      </td>
                      <td class="px-4 py-2.5 text-right">
                        <.pct_badge value={grade_row.primary_math} color="info" />
                      </td>
                      <td :if={@compare} class="px-4 py-2.5 text-right">
                        <.pct_badge value={grade_row.compare_math} color="warning" />
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          <%!-- ── Proficiency Distribution ───────────────────────────────────────── --%>
          <div :if={@primary && @primary.proficiency_dist} class="space-y-3">
            <div class="flex items-center gap-2">
              <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
                Proficiency Level Distribution — All M-STEP Subjects
              </h2>
              <div class="flex-1 h-px bg-base-200"></div>
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
              <.dist_card
                district={@primary}
                color_class="border-info/30 bg-info/5"
                label="Primary"
              />
              <.dist_card
                :if={@compare && @compare.proficiency_dist}
                district={@compare}
                color_class="border-warning/30 bg-warning/5"
                label="Comparison"
              />
              <div
                :if={!@compare}
                class="bg-base-50 border border-dashed border-base-300 flex items-center justify-center py-10 text-sm text-base-content/30"
              >
                No comparison district selected
              </div>
            </div>
          </div>
        </div>

        <%!-- ══ Tab 1: School vs Geographic LEA ════════════════════════════════════ --%>
        <div :if={@active_tab == "school_vs_lea"} class="space-y-6">
          <%!-- Building selector — only shown when district has multiple buildings --%>
          <div
            :if={length(@district_buildings) > 1}
            class="bg-base-100 border border-base-200 p-5 space-y-3"
          >
            <div class="text-xs font-semibold uppercase tracking-wider text-base-content/40">
              Select a School Building
            </div>
            <form phx-change="select_building">
              <select
                name="building"
                class="w-full border border-base-300 bg-base-100 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-info/25 focus:border-info transition-all"
              >
                <option value="">— Select a building —</option>
                <option
                  :for={b <- @district_buildings}
                  value={b.building_code}
                  selected={b.building_code == @selected_building_code}
                >
                  {b.building_name} ({b.building_code})
                </option>
              </select>
            </form>
          </div>

          <%!-- Prompt when multi-building district but nothing selected yet --%>
          <div
            :if={length(@district_buildings) > 1 && is_nil(@selected_building_code)}
            class="bg-base-50 border border-dashed border-base-300 flex items-center justify-center py-16 text-sm text-base-content/30"
          >
            Select a building above to view the comparison
          </div>

          <%!-- Results --%>
          <div :if={@school_vs_lea} class="space-y-6">
            <%!-- Info banner + download button --%>
            <div class="flex flex-col sm:flex-row sm:items-start gap-4">
              <div class="flex-1 grid grid-cols-1 lg:grid-cols-2 gap-4">
                <div class="bg-base-100 border border-info/30 p-5 space-y-1">
                  <div class="text-xs font-semibold uppercase tracking-wider text-info/60">
                    School
                  </div>
                  <div class="font-bold text-base">{@school_vs_lea.school_name}</div>
                  <div class="text-xs text-base-content/50">{@school_vs_lea.building_code}</div>
                </div>

                <div
                  :if={@school_vs_lea.no_lea_found}
                  class="bg-base-100 border border-warning/30 p-5 flex items-center"
                >
                  <p class="text-sm text-warning">
                    No geographic LEA district mapping found for this building in the MDE Entity Master.
                  </p>
                </div>

                <div
                  :if={!@school_vs_lea.no_lea_found}
                  class="bg-base-100 border border-warning/30 p-5 space-y-1"
                >
                  <div class="text-xs font-semibold uppercase tracking-wider text-warning/60">
                    Geographic LEA District
                  </div>
                  <div class="font-bold text-base">
                    {@school_vs_lea.lea_district_name || @school_vs_lea.lea_district_code}
                  </div>
                  <div class="text-xs text-base-content/50">{@school_vs_lea.lea_district_code}</div>
                </div>
              </div>

              <%!-- Download PDF button — only when LEA data is available --%>
              <div :if={!@school_vs_lea.no_lea_found && !@school_vs_lea.no_results} class="shrink-0">
                <.link
                  href={
                    ~p"/mde/lea-comparison.pdf?building=#{@selected_building_code}&year=#{@selected_year}"
                  }
                  target="_blank"
                  class="inline-flex items-center gap-2 px-4 py-2.5 bg-info text-white text-sm font-semibold hover:bg-info/90 transition-colors"
                >
                  <.icon name="hero-arrow-down-tray" class="size-4" /> Download PDF
                </.link>
              </div>
            </div>

            <%!-- No results notice --%>
            <div
              :if={@school_vs_lea.no_results}
              class="bg-warning/5 border border-warning/20 p-4 text-sm text-warning"
            >
              No M-STEP building-level results found for this school in {@selected_year}.
            </div>

            <div
              :if={!@school_vs_lea.no_lea_found && @school_vs_lea.no_lea_results}
              class="bg-warning/5 border border-warning/20 p-4 text-sm text-warning"
            >
              No M-STEP district-level rollup found for the geographic LEA ({@school_vs_lea.lea_district_code}) in {@selected_year}.
              District rollup data may not be imported yet.
            </div>

            <div
              :if={@school_vs_lea.no_state_results}
              class="bg-base-50 border border-base-200 p-4 text-sm text-base-content/50"
            >
              No Michigan state-wide average found for {@selected_year}. State benchmark not available for this year.
            </div>

            <%!-- All Subjects Average --%>
            <div
              :if={!@school_vs_lea.no_results && !@school_vs_lea.no_lea_found}
              class="space-y-3"
            >
              <div class="flex items-center gap-2">
                <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
                  All Subjects Average
                </h2>
                <div class="flex-1 h-px bg-base-200"></div>
              </div>

              <div class="bg-base-100 border border-base-200 p-5">
                <.subject_comparison
                  subject="All Subjects"
                  primary={@school_vs_lea.avg_subjects.school}
                  primary_label={short_name(@school_vs_lea.school_name)}
                  compare={@school_vs_lea.avg_subjects.lea}
                  compare_label={
                    short_name(
                      @school_vs_lea.lea_district_name || @school_vs_lea.lea_district_code ||
                        "LEA"
                    )
                  }
                  state={@school_vs_lea.avg_subjects.state}
                  state_label="State Avg"
                />
              </div>
            </div>

            <%!-- Subject proficiency comparison --%>
            <div
              :if={!@school_vs_lea.no_results && !@school_vs_lea.no_lea_found}
              class="space-y-3"
            >
              <div class="flex items-center gap-2">
                <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
                  M-STEP Proficiency by Subject
                </h2>
                <div class="flex-1 h-px bg-base-200"></div>
              </div>

              <div class="bg-base-100 border border-base-200 p-5 space-y-5">
                <.subject_comparison
                  :for={subject <- @subjects}
                  subject={subject}
                  primary={Map.get(@school_vs_lea.all_subjects, subject) |> then(& &1[:school])}
                  primary_label={short_name(@school_vs_lea.school_name)}
                  compare={Map.get(@school_vs_lea.all_subjects, subject) |> then(& &1[:lea])}
                  compare_label={
                    short_name(
                      @school_vs_lea.lea_district_name || @school_vs_lea.lea_district_code || "LEA"
                    )
                  }
                  state={Map.get(@school_vs_lea.all_subjects, subject) |> then(& &1[:state])}
                  state_label="State Avg"
                />
              </div>
            </div>

            <%!-- Grade breakdown --%>
            <div
              :if={
                !@school_vs_lea.no_results && !@school_vs_lea.no_lea_found &&
                  @school_vs_lea.grade_breakdown != []
              }
              class="space-y-3"
            >
              <div class="flex items-center gap-2">
                <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
                  Grade-Level Breakdown — ELA &amp; Math
                </h2>
                <div class="flex-1 h-px bg-base-200"></div>
              </div>

              <div class="bg-base-100 border border-base-200 overflow-hidden">
                <div class="overflow-x-auto">
                  <table class="w-full text-sm">
                    <thead>
                      <tr class="border-b border-base-200 bg-base-50">
                        <th class="text-left px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          Grade
                        </th>
                        <th class="text-right px-4 py-3 text-xs font-medium text-info uppercase tracking-wide">
                          ELA — School
                        </th>
                        <th class="text-right px-4 py-3 text-xs font-medium text-warning uppercase tracking-wide">
                          ELA — LEA
                        </th>
                        <th class="text-right px-4 py-3 text-xs font-medium text-success uppercase tracking-wide">
                          ELA — State
                        </th>
                        <th class="text-right px-4 py-3 text-xs font-medium text-info uppercase tracking-wide">
                          Math — School
                        </th>
                        <th class="text-right px-4 py-3 text-xs font-medium text-warning uppercase tracking-wide">
                          Math — LEA
                        </th>
                        <th class="text-right px-4 py-3 text-xs font-medium text-success uppercase tracking-wide">
                          Math — State
                        </th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-base-200">
                      <tr :for={row <- @school_vs_lea.grade_breakdown} class="hover:bg-base-50">
                        <td class="px-4 py-2.5 font-medium text-xs">{grade_label(row.grade)}</td>
                        <td class="px-4 py-2.5 text-right">
                          <.pct_badge value={row.school_ela} color="info" />
                        </td>
                        <td class="px-4 py-2.5 text-right">
                          <.pct_badge value={row.lea_ela} color="warning" />
                        </td>
                        <td class="px-4 py-2.5 text-right">
                          <.pct_badge value={row.state_ela} color="success" />
                        </td>
                        <td class="px-4 py-2.5 text-right">
                          <.pct_badge value={row.school_math} color="info" />
                        </td>
                        <td class="px-4 py-2.5 text-right">
                          <.pct_badge value={row.lea_math} color="warning" />
                        </td>
                        <td class="px-4 py-2.5 text-right">
                          <.pct_badge value={row.state_math} color="success" />
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
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

  attr :district, :map, default: nil
  attr :label, :string, default: nil
  attr :color, :string, default: "info"

  def district_header(%{district: nil} = assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-200 p-5 flex items-center justify-center text-base-content/30 text-sm py-10">
      No data found for this district
    </div>
    """
  end

  def district_header(assigns) do
    ~H"""
    <div class={"bg-base-100 border border-#{@color}/30 p-5 space-y-2"}>
      <div :if={@label} class={"text-xs font-semibold uppercase tracking-wider text-#{@color}/60"}>
        {@label}
      </div>
      <div class="font-bold text-base leading-tight">{@district.district_name}</div>
      <div class="flex flex-wrap gap-x-2 gap-y-0.5 text-xs text-base-content/50">
        <span :if={@district.isd_name} class="flex items-center gap-1">
          <.icon name="hero-map-pin" class="size-3" />
          {@district.isd_name} ISD
        </span>
        <span :if={@district.isd_name}>·</span>
        <span :if={@district.entity_type}>{@district.entity_type}</span>
        <span :if={@district.entity_type}>·</span>
        <span>
          {@district.buildings} {if @district.buildings == 1, do: "building", else: "buildings"}
        </span>
        <span :if={@district.total_assessed > 0}>·</span>
        <span :if={@district.total_assessed > 0}>
          {format_number(@district.total_assessed)} students
        </span>
      </div>
    </div>
    """
  end

  attr :subject, :string, required: true
  attr :primary, :any, default: nil
  attr :primary_label, :string, default: "Primary"
  attr :compare, :any, default: nil
  attr :compare_label, :string, default: nil
  attr :state, :any, default: nil
  attr :state_label, :string, default: "State Avg"

  def subject_comparison(assigns) do
    primary_f = if assigns.primary, do: Decimal.to_float(assigns.primary), else: nil
    compare_f = if assigns.compare, do: Decimal.to_float(assigns.compare), else: nil
    state_f = if assigns.state, do: Decimal.to_float(assigns.state), else: nil

    assigns =
      assigns
      |> assign(:primary_f, primary_f)
      |> assign(:compare_f, compare_f)
      |> assign(:state_f, state_f)

    ~H"""
    <div class="space-y-1.5">
      <div class="flex items-center justify-between text-xs mb-1">
        <span class="font-semibold text-base-content/70">{@subject}</span>
        <div class="flex items-center gap-4">
          <span :if={@state_f} class="flex items-center gap-1.5">
            <span class="inline-block w-2 h-2 rounded-full bg-success"></span>
            <span class="tabular-nums text-success font-semibold">
              {if @state, do: "#{@state}%", else: "—"}
            </span>
          </span>
          <span :if={@compare_f} class="flex items-center gap-1.5">
            <span class="inline-block w-2 h-2 rounded-full bg-warning"></span>
            <span class="tabular-nums text-warning font-semibold">
              {if @compare, do: "#{@compare}%", else: "—"}
            </span>
          </span>
          <span class="flex items-center gap-1.5">
            <span class="inline-block w-2 h-2 rounded-full bg-info"></span>
            <span class="tabular-nums text-info font-semibold">
              {if @primary, do: "#{@primary}%", else: "—"}
            </span>
          </span>
        </div>
      </div>

      <%!-- Primary bar --%>
      <div class="flex items-center gap-2">
        <span class="text-xs text-base-content/40 w-20 truncate text-right">
          {@primary_label}
        </span>
        <div class="flex-1 bg-base-200 h-5 relative">
          <div
            class="h-5 bg-info/70 transition-all duration-500"
            style={"width: #{if @primary_f, do: min(@primary_f, 100), else: 0}%"}
          >
          </div>
          <%!-- LEA comparison marker on primary bar --%>
          <div
            :if={@compare_f}
            class="absolute top-0 bottom-0 w-0.5 bg-warning"
            style={"left: #{min(@compare_f, 100)}%"}
            title={"#{@compare_label}: #{@compare_f}%"}
          >
          </div>
        </div>
      </div>

      <%!-- Compare bar (shown when compare is selected) --%>
      <div :if={@compare_label} class="flex items-center gap-2">
        <span class="text-xs text-base-content/40 w-20 truncate text-right">
          {@compare_label}
        </span>
        <div class="flex-1 bg-base-200 h-5 relative">
          <div
            class="h-5 bg-warning/70 transition-all duration-500"
            style={"width: #{if @compare_f, do: min(@compare_f, 100), else: 0}%"}
          >
          </div>
          <%!-- Primary marker on compare bar --%>
          <div
            :if={@primary_f}
            class="absolute top-0 bottom-0 w-0.5 bg-info"
            style={"left: #{min(@primary_f, 100)}%"}
            title={"#{@primary_label}: #{@primary_f}%"}
          >
          </div>
        </div>
      </div>

      <%!-- State bar (shown when state data is available) --%>
      <div :if={@state} class="flex items-center gap-2">
        <span class="text-xs text-base-content/40 w-20 truncate text-right">
          {@state_label}
        </span>
        <div class="flex-1 bg-base-200 h-5 relative">
          <div
            class="h-5 bg-success/70 transition-all duration-500"
            style={"width: #{if @state_f, do: min(@state_f, 100), else: 0}%"}
          >
          </div>
          <%!-- Primary marker on state bar --%>
          <div
            :if={@primary_f}
            class="absolute top-0 bottom-0 w-0.5 bg-info"
            style={"left: #{min(@primary_f, 100)}%"}
            title={"#{@primary_label}: #{@primary_f}%"}
          >
          </div>
        </div>
      </div>

      <%!-- Delta badges when relevant data is present --%>
      <div :if={@primary_f && (@compare_f || @state_f)} class="flex justify-end gap-2">
        <% delta_compare =
          if @primary_f && @compare_f, do: Float.round(@primary_f - @compare_f, 1), else: nil %>
        <% delta_state =
          if @primary_f && @state_f, do: Float.round(@primary_f - @state_f, 1), else: nil %>
        <span
          :if={delta_compare}
          class={[
            "text-xs font-semibold tabular-nums px-1.5 py-0.5",
            if(delta_compare >= 0, do: "text-success bg-success/10", else: "text-error bg-error/10")
          ]}
        >
          {if delta_compare >= 0, do: "+#{delta_compare}", else: "#{delta_compare}"} pts vs {@compare_label ||
            "comparison"}
        </span>
        <span
          :if={delta_state}
          class={[
            "text-xs font-semibold tabular-nums px-1.5 py-0.5",
            if(delta_state >= 0, do: "text-success bg-success/10", else: "text-error bg-error/10")
          ]}
        >
          {if delta_state >= 0, do: "+#{delta_state}", else: "#{delta_state}"} pts vs {@state_label}
        </span>
      </div>
    </div>
    """
  end

  attr :value, :any, default: nil
  attr :color, :string, default: "info"

  def pct_badge(assigns) do
    ~H"""
    <span class={"font-semibold tabular-nums text-#{@color}"}>
      {if @value, do: "#{@value}%", else: "—"}
    </span>
    """
  end

  attr :district, :map, required: true
  attr :color_class, :string, default: "border-base-200 bg-base-50"
  attr :label, :string, default: ""

  def dist_card(assigns) do
    ~H"""
    <div class={"border p-5 space-y-3 #{@color_class}"}>
      <div class="font-semibold text-sm truncate">{@district.district_name}</div>

      <div class="flex h-6 w-full overflow-hidden">
        <div
          class="bg-success flex items-center justify-center text-xs text-white font-semibold"
          style={"width: #{@district.proficiency_dist.advanced}%"}
          title={"Advanced: #{@district.proficiency_dist.advanced}%"}
        >
          {if @district.proficiency_dist.advanced >= 8,
            do: "#{@district.proficiency_dist.advanced}%",
            else: ""}
        </div>
        <div
          class="bg-info flex items-center justify-center text-xs text-white font-semibold"
          style={"width: #{@district.proficiency_dist.proficient}%"}
          title={"Proficient: #{@district.proficiency_dist.proficient}%"}
        >
          {if @district.proficiency_dist.proficient >= 8,
            do: "#{@district.proficiency_dist.proficient}%",
            else: ""}
        </div>
        <div
          class="bg-warning flex items-center justify-center text-xs text-white font-semibold"
          style={"width: #{@district.proficiency_dist.partially}%"}
          title={"Partially: #{@district.proficiency_dist.partially}%"}
        >
          {if @district.proficiency_dist.partially >= 8,
            do: "#{@district.proficiency_dist.partially}%",
            else: ""}
        </div>
        <div
          class="bg-error flex-1 flex items-center justify-center text-xs text-white font-semibold"
          title={"Not Proficient: #{@district.proficiency_dist.not_proficient}%"}
        >
          {if @district.proficiency_dist.not_proficient >= 8,
            do: "#{@district.proficiency_dist.not_proficient}%",
            else: ""}
        </div>
      </div>

      <div class="grid grid-cols-2 gap-x-4 gap-y-1">
        <span class="flex items-center gap-1.5 text-xs text-base-content/60">
          <span class="inline-block w-2 h-2 rounded-sm bg-success"></span>
          Advanced {@district.proficiency_dist.advanced}%
        </span>
        <span class="flex items-center gap-1.5 text-xs text-base-content/60">
          <span class="inline-block w-2 h-2 rounded-sm bg-info"></span>
          Proficient {@district.proficiency_dist.proficient}%
        </span>
        <span class="flex items-center gap-1.5 text-xs text-base-content/60">
          <span class="inline-block w-2 h-2 rounded-sm bg-warning"></span>
          Partially {@district.proficiency_dist.partially}%
        </span>
        <span class="flex items-center gap-1.5 text-xs text-base-content/60">
          <span class="inline-block w-2 h-2 rounded-sm bg-error"></span>
          Not Prof. {@district.proficiency_dist.not_proficient}%
        </span>
      </div>
    </div>
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

  defp load_all_districts do
    MdeDistrict
    |> Ash.Query.sort(:district_name)
    |> Ash.read!(authorize?: false)
  end

  defp load_district_data(district_code, year) do
    snapshot =
      MdeDistrictSnapshot
      |> Ash.Query.filter(district_code == ^district_code and school_year == ^year)
      |> Ash.read_one!(authorize?: false)

    case snapshot do
      nil ->
        nil

      snap ->
        %{
          district_code: snap.district_code,
          district_name: snap.district_name || district_code,
          entity_type: snap.entity_type,
          isd_name: snap.isd_name,
          buildings: snap.buildings || 0,
          total_assessed: snap.total_assessed || 0,
          all_subjects: convert_snapshot_subjects(snap.all_subjects),
          grade_breakdown: convert_snapshot_grade_breakdown(snap.grade_breakdown),
          proficiency_dist: convert_snapshot_proficiency_dist(snap.proficiency_dist)
        }
    end
  end

  defp load_district_buildings(district_code) do
    MdeBuilding
    |> Ash.Query.filter(mde_district.district_code == ^district_code)
    |> Ash.Query.sort(:building_name)
    |> Ash.read!(authorize?: false)
  end

  defp load_school_vs_lea(building_code, year) do
    snapshot =
      MdeSchoolVsLeaSnapshot
      |> Ash.Query.for_read(:by_building_and_year, %{
        building_code: building_code,
        school_year: year
      })
      |> Ash.read_one!(authorize?: false)

    case snapshot do
      nil ->
        %{
          building_code: building_code,
          school_name: building_code,
          lea_district_code: nil,
          lea_district_name: nil,
          no_lea_found: false,
          no_results: true,
          no_lea_results: true,
          no_state_results: true,
          all_subjects: %{},
          avg_subjects: %{school: nil, lea: nil, state: nil},
          grade_breakdown: []
        }

      snap ->
        %{
          building_code: snap.building_code,
          school_name: snap.school_name || building_code,
          lea_district_code: snap.lea_district_code,
          lea_district_name: snap.lea_district_name,
          no_lea_found: snap.no_lea_found,
          no_results: snap.no_results,
          no_lea_results: snap.no_lea_results,
          no_state_results: snap.no_state_results,
          all_subjects: convert_snap_subject_comparison(snap.subject_comparison),
          avg_subjects: convert_snap_all_subjects_avg(snap.all_subjects_avg),
          grade_breakdown: convert_snap_grade_comparison(snap.grade_breakdown)
        }
    end
  end

  # ---------------------------------------------------------------------------
  # Snapshot → template shape converters
  # JSONB round-trip produces string-keyed maps and floats; convert to the
  # atom-keyed / Decimal shapes that existing components expect.
  # ---------------------------------------------------------------------------

  defp float_to_decimal(nil), do: nil
  defp float_to_decimal(f) when is_float(f), do: Decimal.from_float(f)

  defp convert_snapshot_subjects(nil), do: %{}

  defp convert_snapshot_subjects(map) do
    Map.new(map, fn {k, v} -> {k, float_to_decimal(v)} end)
  end

  defp convert_snapshot_grade_breakdown(nil), do: []

  defp convert_snapshot_grade_breakdown(list) do
    list
    |> Enum.map(fn row ->
      %{
        grade: row["grade"],
        ela: float_to_decimal(row["ela"]),
        math: float_to_decimal(row["math"]),
        students: row["students"] || 0
      }
    end)
    |> Enum.sort_by(& &1.grade)
  end

  defp convert_snapshot_proficiency_dist(nil), do: nil

  defp convert_snapshot_proficiency_dist(map) do
    %{
      advanced: map["advanced"],
      proficient: map["proficient"],
      partially: map["partially"],
      not_proficient: map["not_proficient"]
    }
  end

  # subject_comparison list → %{subject => %{school: Decimal, lea: Decimal, state: Decimal}}
  defp convert_snap_subject_comparison(nil), do: %{}

  defp convert_snap_subject_comparison(list) do
    Map.new(list, fn row ->
      {row["subject"],
       %{
         school: float_to_decimal(row["school_pct"]),
         lea: float_to_decimal(row["lea_pct"]),
         state: float_to_decimal(row["state_pct"])
       }}
    end)
  end

  # all_subjects_avg map → %{school: Decimal, lea: Decimal, state: Decimal}
  defp convert_snap_all_subjects_avg(nil), do: %{school: nil, lea: nil, state: nil}

  defp convert_snap_all_subjects_avg(map) do
    %{
      school: float_to_decimal(map["school_pct"]),
      lea: float_to_decimal(map["lea_pct"]),
      state: float_to_decimal(map["state_pct"])
    }
  end

  # grade_breakdown list → atom-keyed maps with Decimal values
  defp convert_snap_grade_comparison(nil), do: []

  defp convert_snap_grade_comparison(list) do
    Enum.map(list, fn row ->
      %{
        grade: row["grade"],
        school_ela: float_to_decimal(row["school_ela"]),
        lea_ela: float_to_decimal(row["lea_ela"]),
        state_ela: float_to_decimal(row["state_ela"]),
        school_math: float_to_decimal(row["school_math"]),
        lea_math: float_to_decimal(row["lea_math"]),
        state_math: float_to_decimal(row["state_math"])
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp tab_class(true),
    do: "px-4 py-2.5 text-sm font-semibold border-b-2 border-info text-info"

  defp tab_class(false),
    do:
      "px-4 py-2.5 text-sm font-medium border-b-2 border-transparent text-base-content/50 hover:text-base-content"

  # Merge two grade breakdown lists into aligned rows for the comparison table
  defp align_grades(primary_grades, nil) do
    Enum.map(primary_grades, fn g ->
      %{
        grade: g.grade,
        primary_ela: g.ela,
        primary_math: g.math,
        compare_ela: nil,
        compare_math: nil
      }
    end)
  end

  defp align_grades(primary_grades, compare_grades) do
    compare_map = Map.new(compare_grades, &{&1.grade, &1})

    all_grades =
      (Enum.map(primary_grades, & &1.grade) ++ Enum.map(compare_grades, & &1.grade))
      |> Enum.uniq()
      |> Enum.sort()

    Enum.map(all_grades, fn grade ->
      p = Enum.find(primary_grades, &(&1.grade == grade))
      c = Map.get(compare_map, grade)

      %{
        grade: grade,
        primary_ela: p && p.ela,
        primary_math: p && p.math,
        compare_ela: c && c.ela,
        compare_math: c && c.math
      }
    end)
  end

  defp grade_label("11"), do: "Grade 11"
  defp grade_label(g), do: "Grade #{g}"

  # Truncate long district names for column headers
  defp short_name(nil), do: "—"

  defp short_name(name) when byte_size(name) > 20 do
    String.slice(name, 0, 18) <> "…"
  end

  defp short_name(name), do: name

  defp page_title(nil, _), do: "District Analysis"
  defp page_title(primary, nil), do: "#{primary.district_name} — Analysis"

  defp page_title(primary, compare),
    do: "#{short_name(primary.district_name)} vs #{short_name(compare.district_name)}"

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
