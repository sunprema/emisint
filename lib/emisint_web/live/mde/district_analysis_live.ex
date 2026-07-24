defmodule EmisintWeb.Mde.DistrictAnalysisLive do
  use EmisintWeb, :live_view

  require Ash.Query

  alias Emisint.Assessments.{
    MdeBuilding,
    MdeCompositeResidentDistrict,
    MdeDistrict,
    MdeDistrictSnapshot,
    MdeEnrollmentResult,
    MdeSchoolIndexResult,
    MdeSatResult,
    MdeSchoolVsLeaSnapshot,
    MdeSgpResult,
    MdeStateAssessmentResult
  }

  @subjects ["ELA", "Mathematics", "Science", "Social Studies"]

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  def mount(_params, _session, socket) do
    is_connected = connected?(socket)

    # Defer all DB work to the connected mount — the disconnected (HTTP) pass
    # only renders static HTML so loading data there is wasteful.
    {years, all_districts} =
      if is_connected do
        years_task = Task.async(fn -> load_school_years() end)
        districts_task = Task.async(fn -> load_all_districts() end)
        {Task.await(years_task), Task.await(districts_task)}
      else
        {[], []}
      end

    selected_year = List.last(years) || ""

    {:ok,
     socket
     |> assign(:is_connected, is_connected)
     |> assign(:page_title, "District Analysis")
     |> assign(:school_years, years)
     |> assign(:selected_year, selected_year)
     |> assign(:all_districts, all_districts)
     |> assign(:district_code, nil)
     |> assign(:from, nil)
     |> assign(:from_agency, nil)
     |> assign(:from_agency_name, nil)
     |> assign(:from_emo, nil)
     |> assign(:compare_code, "")
     |> assign(:primary, nil)
     |> assign(:compare, nil)
     |> assign(:primary_sgp, %{subjects: [], grades: []})
     |> assign(:compare_sgp, %{subjects: [], grades: []})
     |> assign(:active_tab, "school_vs_lea")
     |> assign(:district_buildings, [])
     |> assign(:selected_building_code, nil)
     |> assign(:enrollment, nil)
     |> assign(:school_vs_lea, nil)
     |> assign(:sat_results, [])
     |> assign(:sat_lea_result, nil)
     |> assign(:lea_enrollment, nil)
     |> assign(:sat_state_result, nil)
     |> assign(:econ_grade_breakdown, [])
     |> assign(:school_index, nil)
     |> assign(:index_thresholds, %{})
     |> assign(:sgp_results, %{subjects: [], grades: []})
     |> assign(:sgp_lea_result, %{subjects: [], grades: []})
     |> assign(:sgp_subject_filter, nil)
     |> assign(:crd_comparison, nil)
     |> assign(:crd_scope, "all")}
  end

  def handle_params(%{"district_code" => dc} = params, _uri, socket) do
    tab = Map.get(params, "tab", "school_vs_lea")
    building_code = Map.get(params, "building", nil)
    year = socket.assigns.selected_year
    compare_code = Map.get(params, "compare", "")
    from = Map.get(params, "from", nil)
    from_agency = Map.get(params, "agency", nil)
    from_agency_name = Map.get(params, "agency_name", from_agency)
    from_emo = Map.get(params, "emo", nil)

    # Skip DB work on the disconnected (HTTP) pass — only set URL-derived assigns.
    if not socket.assigns.is_connected do
      {:noreply,
       socket
       |> assign(:district_code, dc)
       |> assign(:from, from)
       |> assign(:from_agency, from_agency)
       |> assign(:from_agency_name, from_agency_name)
       |> assign(:from_emo, from_emo)
       |> assign(:compare_code, compare_code)
       |> assign(:active_tab, tab)}
    else
      # ── District comparison tab: independent snapshot + SGP lookups → parallel ──
      {primary, compare, primary_sgp, compare_sgp} =
        if tab == "district_comparison" do
          p_task = if year != "", do: Task.async(fn -> load_district_data(dc, year) end)

          c_task =
            if compare_code != "" && year != "",
              do: Task.async(fn -> load_district_data(compare_code, year) end)

          p_sgp_task = if year != "", do: Task.async(fn -> load_sgp_lea_result(dc, year) end)

          c_sgp_task =
            if compare_code != "" && year != "",
              do: Task.async(fn -> load_sgp_lea_result(compare_code, year) end)

          {if(p_task, do: Task.await(p_task)), if(c_task, do: Task.await(c_task)),
           if(p_sgp_task, do: Task.await(p_sgp_task), else: %{subjects: [], grades: []}),
           if(c_sgp_task, do: Task.await(c_sgp_task), else: %{subjects: [], grades: []})}
        else
          {socket.assigns.primary, socket.assigns.compare, socket.assigns.primary_sgp,
           socket.assigns.compare_sgp}
        end

      # Buildings lookup runs first — tiny indexed query needed to resolve
      # effective_building_code before the parallel batches below.
      district_buildings =
        if tab == "school_vs_lea", do: load_district_buildings(dc), else: []

      effective_building_code =
        building_code ||
          case district_buildings do
            [sole] -> sole.building_code
            _ -> nil
          end

      # ── Batch 1: five independent queries → parallel ───────────────────────────
      {school_vs_lea, enrollment, sat_results, sat_state_result, school_index, sgp_results} =
        if tab == "school_vs_lea" && effective_building_code && year != "" do
          t1 = Task.async(fn -> load_school_vs_lea(effective_building_code, year) end)
          t2 = Task.async(fn -> load_enrollment(effective_building_code, year) end)
          t3 = Task.async(fn -> load_sat_results(effective_building_code, year) end)
          t4 = Task.async(fn -> load_sat_state_result(year) end)
          t5 = Task.async(fn -> load_school_index(effective_building_code, year) end)
          t6 = Task.async(fn -> load_sgp_results(effective_building_code, year) end)

          {Task.await(t1), Task.await(t2), Task.await(t3), Task.await(t4), Task.await(t5),
           Task.await(t6)}
        else
          {nil, nil, [], nil, nil, %{subjects: [], grades: []}}
        end

      # ── Batch 2: queries that depend on lea_dc from batch 1 → parallel ───────
      lea_dc = school_vs_lea && school_vs_lea.lea_district_code

      {sat_lea_result, lea_enrollment, econ_grade_breakdown, sgp_lea_result} =
        if tab == "school_vs_lea" && effective_building_code && year != "" do
          sat_lea_task =
            if school_vs_lea && !school_vs_lea.no_lea_found && lea_dc,
              do: Task.async(fn -> load_sat_lea_result(lea_dc, year) end)

          lea_enrollment_task =
            if school_vs_lea && !school_vs_lea.no_lea_found && lea_dc,
              do: Task.async(fn -> load_lea_enrollment(lea_dc, year) end)

          econ_task =
            Task.async(fn ->
              load_econ_grade_breakdown(effective_building_code, lea_dc, year)
            end)

          sgp_lea_task =
            if school_vs_lea && !school_vs_lea.no_lea_found && lea_dc,
              do: Task.async(fn -> load_sgp_lea_result(lea_dc, year) end)

          {if(sat_lea_task, do: Task.await(sat_lea_task)),
           if(lea_enrollment_task, do: Task.await(lea_enrollment_task)), Task.await(econ_task),
           if(sgp_lea_task, do: Task.await(sgp_lea_task), else: %{subjects: [], grades: []})}
        else
          {nil, nil, [], %{subjects: [], grades: []}}
        end

      index_thresholds = if year != "", do: load_index_thresholds(year), else: %{}

      crd_comparison =
        if tab == "crd_comparison" && year != "",
          do: load_crd_comparison(dc, year),
          else: socket.assigns.crd_comparison

      {:noreply,
       socket
       |> assign(:district_code, dc)
       |> assign(:from, from)
       |> assign(:from_agency, from_agency)
       |> assign(:from_agency_name, from_agency_name)
       |> assign(:from_emo, from_emo)
       |> assign(:compare_code, compare_code)
       |> assign(:active_tab, tab)
       |> assign(:primary, primary)
       |> assign(:compare, compare)
       |> assign(:primary_sgp, primary_sgp)
       |> assign(:compare_sgp, compare_sgp)
       |> assign(:crd_comparison, crd_comparison)
       |> assign(:district_buildings, district_buildings)
       |> assign(:selected_building_code, effective_building_code)
       |> assign(:enrollment, enrollment)
       |> assign(:lea_enrollment, lea_enrollment)
       |> assign(:school_vs_lea, school_vs_lea)
       |> assign(:sat_results, sat_results)
       |> assign(:sat_lea_result, sat_lea_result)
       |> assign(:sat_state_result, sat_state_result)
       |> assign(:econ_grade_breakdown, econ_grade_breakdown)
       |> assign(:school_index, school_index)
       |> assign(:index_thresholds, index_thresholds)
       |> assign(:sgp_results, sgp_results)
       |> assign(:sgp_lea_result, sgp_lea_result)
       |> assign(:page_title, page_title(primary, compare))}
    end
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  def handle_event("select_year", %{"year" => year}, socket) do
    dc = socket.assigns.district_code
    tab = socket.assigns.active_tab

    effective_building_code =
      socket.assigns.selected_building_code ||
        case socket.assigns.district_buildings do
          [sole] -> sole.building_code
          _ -> nil
        end

    # ── District comparison tab: independent snapshot + SGP lookups → parallel ──
    {primary, compare, primary_sgp, compare_sgp} =
      if tab == "district_comparison" do
        p_task = if dc && year != "", do: Task.async(fn -> load_district_data(dc, year) end)

        c_task =
          if socket.assigns.compare_code != "" && year != "",
            do: Task.async(fn -> load_district_data(socket.assigns.compare_code, year) end)

        p_sgp_task = if dc && year != "", do: Task.async(fn -> load_sgp_lea_result(dc, year) end)

        c_sgp_task =
          if socket.assigns.compare_code != "" && year != "",
            do: Task.async(fn -> load_sgp_lea_result(socket.assigns.compare_code, year) end)

        {if(p_task, do: Task.await(p_task)), if(c_task, do: Task.await(c_task)),
         if(p_sgp_task, do: Task.await(p_sgp_task), else: %{subjects: [], grades: []}),
         if(c_sgp_task, do: Task.await(c_sgp_task), else: %{subjects: [], grades: []})}
      else
        {socket.assigns.primary, socket.assigns.compare, socket.assigns.primary_sgp,
         socket.assigns.compare_sgp}
      end

    # ── Batch 1: five independent queries → parallel ───────────────────────────
    {school_vs_lea, enrollment, sat_results, sat_state_result, school_index, sgp_results} =
      if tab == "school_vs_lea" && effective_building_code && year != "" do
        t1 = Task.async(fn -> load_school_vs_lea(effective_building_code, year) end)
        t2 = Task.async(fn -> load_enrollment(effective_building_code, year) end)
        t3 = Task.async(fn -> load_sat_results(effective_building_code, year) end)
        t4 = Task.async(fn -> load_sat_state_result(year) end)
        t5 = Task.async(fn -> load_school_index(effective_building_code, year) end)
        t6 = Task.async(fn -> load_sgp_results(effective_building_code, year) end)

        {Task.await(t1), Task.await(t2), Task.await(t3), Task.await(t4), Task.await(t5),
         Task.await(t6)}
      else
        {socket.assigns.school_vs_lea, socket.assigns.enrollment, socket.assigns.sat_results,
         socket.assigns.sat_state_result, socket.assigns.school_index, socket.assigns.sgp_results}
      end

    # ── Batch 2: queries that depend on lea_dc from batch 1 → parallel ───────
    lea_dc = school_vs_lea && school_vs_lea.lea_district_code

    {sat_lea_result, lea_enrollment, econ_grade_breakdown, sgp_lea_result} =
      if tab == "school_vs_lea" && effective_building_code && year != "" do
        sat_lea_task =
          if school_vs_lea && !school_vs_lea.no_lea_found && lea_dc,
            do: Task.async(fn -> load_sat_lea_result(lea_dc, year) end)

        lea_enrollment_task =
          if school_vs_lea && !school_vs_lea.no_lea_found && lea_dc,
            do: Task.async(fn -> load_lea_enrollment(lea_dc, year) end)

        econ_task =
          Task.async(fn ->
            load_econ_grade_breakdown(effective_building_code, lea_dc, year)
          end)

        sgp_lea_task =
          if school_vs_lea && !school_vs_lea.no_lea_found && lea_dc,
            do: Task.async(fn -> load_sgp_lea_result(lea_dc, year) end)

        {if(sat_lea_task, do: Task.await(sat_lea_task)),
         if(lea_enrollment_task, do: Task.await(lea_enrollment_task)), Task.await(econ_task),
         if(sgp_lea_task, do: Task.await(sgp_lea_task), else: %{subjects: [], grades: []})}
      else
        {socket.assigns.sat_lea_result, socket.assigns.lea_enrollment,
         socket.assigns.econ_grade_breakdown, socket.assigns.sgp_lea_result}
      end

    index_thresholds = if year != "", do: load_index_thresholds(year), else: %{}

    crd_comparison =
      if tab == "crd_comparison" && dc && year != "",
        do: load_crd_comparison(dc, year),
        else: socket.assigns.crd_comparison

    {:noreply,
     socket
     |> assign(:selected_year, year)
     |> assign(:primary, primary)
     |> assign(:compare, compare)
     |> assign(:primary_sgp, primary_sgp)
     |> assign(:compare_sgp, compare_sgp)
     |> assign(:crd_comparison, crd_comparison)
     |> assign(:enrollment, enrollment)
     |> assign(:lea_enrollment, lea_enrollment)
     |> assign(:school_vs_lea, school_vs_lea)
     |> assign(:sat_results, sat_results)
     |> assign(:sat_lea_result, sat_lea_result)
     |> assign(:sat_state_result, sat_state_result)
     |> assign(:econ_grade_breakdown, econ_grade_breakdown)
     |> assign(:school_index, school_index)
     |> assign(:index_thresholds, index_thresholds)
     |> assign(:sgp_results, sgp_results)
     |> assign(:sgp_lea_result, sgp_lea_result)}
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

  # CRD scope toggle — pure view switch over already-loaded data, no reload.
  def handle_event("select_crd_scope", %{"scope" => scope}, socket)
      when scope in ["all", "top10"] do
    {:noreply, assign(socket, :crd_scope, scope)}
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

  def handle_event("toggle_sgp_subject", %{"subject" => subject}, socket) do
    all_subjects =
      sgp_comparison_rows(socket.assigns.sgp_results, socket.assigns.sgp_lea_result).subjects

    current = socket.assigns.sgp_subject_filter || MapSet.new(all_subjects)

    new_filter =
      if MapSet.member?(current, subject) do
        MapSet.delete(current, subject)
      else
        MapSet.put(current, subject)
      end

    {:noreply, assign(socket, :sgp_subject_filter, new_filter)}
  end

  def handle_event("reset_sgp_subject_filter", _params, socket) do
    {:noreply, assign(socket, :sgp_subject_filter, nil)}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  def render(assigns) do
    assigns =
      assigns
      |> assign(:subjects, @subjects)
      |> assign(:crd_view, crd_view(assigns))

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-6xl mx-auto space-y-8">
        <%!-- Top bar: breadcrumbs + year selector --%>
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div class="flex flex-col gap-1.5">
            <.breadcrumbs items={build_breadcrumbs(assigns)} />
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
          <button
            phx-click="select_tab"
            phx-value-tab="crd_comparison"
            class={tab_class(@active_tab == "crd_comparison")}
          >
            CRD Comparison
          </button>
        </div>

        <%!-- ══ Tab 3: CRD Comparison ══════════════════════════════════════════ --%>
        <div :if={@active_tab == "crd_comparison"} class="space-y-6">
          <%!-- Empty state — no CRD rows for this district --%>
          <div
            :if={is_nil(@crd_comparison) || @crd_comparison.total_residents == 0}
            class="bg-base-50 border border-dashed border-base-300 flex flex-col items-center justify-center py-16 px-6 text-center gap-2"
          >
            <.icon name="hero-arrows-right-left" class="size-7 text-base-content/25" />
            <p class="text-sm font-medium text-base-content/50">
              No Composite Resident District data
            </p>

            <p class="text-xs text-base-content/35 max-w-md">
              This district has no rows in the CRD report — either it isn't a charter in the
              Composite Resident District dataset, or CRD data hasn't been imported yet.
            </p>
          </div>

          <div :if={@crd_comparison && @crd_comparison.total_residents > 0} class="space-y-6">
            <%!-- Scope toggle: all resident districts vs top 10 by enrollment --%>
            <div class="flex items-center justify-between gap-3 flex-wrap">
              <p class="text-xs text-base-content/50">
                Compare against
                <span class="font-semibold text-base-content/70">
                  {if @crd_scope == "top10",
                    do: "the top 10 resident districts by enrollment",
                    else: "all resident districts"}
                </span>
              </p>

              <div class="flex items-center gap-3">
                <div class="inline-flex border border-base-300 overflow-hidden">
                  <button
                    phx-click="select_crd_scope"
                    phx-value-scope="all"
                    class={crd_scope_btn_class(@crd_scope == "all")}
                  >
                    All Districts ({@crd_comparison.total_residents})
                  </button>
                  <button
                    phx-click="select_crd_scope"
                    phx-value-scope="top10"
                    class={crd_scope_btn_class(@crd_scope == "top10")}
                  >
                    Top 10
                  </button>
                </div>

                <.link
                  href={
                    ~p"/mde/crd-comparison.pdf?district_code=#{@district_code}&year=#{@selected_year}"
                  }
                  target="_blank"
                  class="inline-flex items-center gap-2 px-3 py-1.5 bg-info text-white text-xs font-semibold hover:bg-info/90 transition-colors"
                >
                  <.icon name="hero-arrow-down-tray" class="size-4" /> Download PDF
                </.link>
              </div>
            </div>
            <%!-- Summary headers: charter vs composite --%>
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
              <div class="bg-base-100 border border-info/30 p-5 space-y-1">
                <div class="text-xs font-semibold uppercase tracking-wider text-info/60">School</div>

                <div class="font-bold text-base leading-tight">
                  {@crd_comparison.charter_name || @district_code}
                </div>

                <div class="text-xs text-base-content/50">{@district_code}</div>
              </div>

              <div class="bg-base-100 border border-warning/30 p-5 space-y-1">
                <div class="flex items-center gap-2">
                  <div class="text-xs font-semibold uppercase tracking-wider text-warning/60">
                    Composite Resident District
                  </div>

                  <span :if={@crd_scope == "top10"} class="badge badge-warning badge-xs">Top 10</span>
                </div>

                <div class="font-bold text-base leading-tight">
                  {@crd_view.scored_count} of {@crd_view.district_count} resident districts with M-STEP data
                </div>

                <div class="text-xs text-base-content/50">
                  Enrollment-weighted by {format_number(@crd_view.total_students)} nonresident students
                </div>
              </div>
            </div>
            <%!-- Scope summary table — All vs Top 10 at a glance --%>
            <.collapsible_section id="composite-summary-crd" title="Composite Summary">
              <div class="border border-base-200 overflow-hidden -mx-5 -mb-5">
                <div class="overflow-x-auto">
                  <table class="w-full text-sm">
                    <thead>
                      <tr class="border-b border-base-200 bg-base-50">
                        <th class="text-left px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          Scope
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          Districts
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          Students
                        </th>

                        <th
                          :for={subject <- @subjects}
                          class="text-right px-4 py-3 text-xs font-medium text-warning uppercase tracking-wide"
                        >
                          {subject_abbr(subject)}
                        </th>
                      </tr>
                    </thead>

                    <tbody class="divide-y divide-base-200">
                      <%!-- School (charter) — the baseline being compared against --%>
                      <tr class="border-b-2 border-base-300 bg-info/5">
                        <td class="px-4 py-2.5 font-semibold text-xs text-info">
                          School
                          <span class="block text-base-content/40 font-normal normal-case">
                            {short_name(@crd_comparison.charter_name || @district_code)}
                          </span>
                        </td>

                        <td class="px-4 py-2.5 text-right text-xs text-base-content/30">—</td>

                        <td class="px-4 py-2.5 text-right text-xs text-base-content/30">—</td>

                        <td :for={subject <- @subjects} class="px-4 py-2.5 text-right">
                          <.pct_badge
                            value={Map.get(@crd_comparison.charter_subjects, subject)}
                            color="info"
                          />
                        </td>
                      </tr>

                      <tr
                        :for={
                          {label, scope, v} <- [
                            {"All", "all", @crd_comparison.all},
                            {"Top 10", "top10", @crd_comparison.top10}
                          ]
                        }
                        class={["hover:bg-base-50", @crd_scope == scope && "bg-warning/5 font-medium"]}
                      >
                        <td class="px-4 py-2.5 font-semibold text-xs">{label}</td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs text-base-content/70">
                          {v.district_count}
                        </td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs text-base-content/70">
                          {format_number(v.total_students)}
                        </td>

                        <td :for={subject <- @subjects} class="px-4 py-2.5 text-right">
                          <.pct_badge value={Map.get(v.composite_subjects, subject)} color="warning" />
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </.collapsible_section>

            <%!-- No scored districts notice --%>
            <div
              :if={@crd_view.scored_count == 0}
              class="bg-warning/5 border border-warning/20 p-4 text-sm text-warning"
            >
              None of these resident districts have M-STEP rollup data for {@selected_year}.
              The composite can't be computed for this scope/year.
            </div>

            <%!-- SGP by Subject — school vs. composite --%>
            <.collapsible_section
              :if={@crd_comparison.has_any_sgp}
              id="sgp-bars-crd"
              title="Student Growth Percentile by Subject"
            >
              <:badge>
                <span :if={@crd_scope == "top10"} class="badge badge-warning badge-xs">
                  Top 10
                </span>
                <span class="text-xs text-base-content/40 normal-case font-normal">
                  Dashed line = 50th percentile (typical growth)
                </span>
              </:badge>
              <.sgp_subject_bar
                :for={subject <- @crd_comparison.sgp_subjects}
                subject={subject}
                primary={Map.get(@crd_comparison.charter_sgp, subject)}
                primary_label={short_name(@crd_comparison.charter_name || @district_code)}
                compare={Map.get(@crd_view.composite_sgp_subjects, subject)}
                compare_label={crd_scope_label(@crd_scope)}
              />
            </.collapsible_section>

            <%!-- SGP numbers: summary + resident district breakdown --%>
            <.collapsible_section
              :if={@crd_comparison.has_any_sgp}
              id="sgp-table-crd"
              title="Student Growth Percentile"
            >
              <:badge>
                <span :if={@crd_scope == "top10"} class="badge badge-warning badge-xs">
                  Top 10
                </span>
              </:badge>
              <%!-- SGP summary table: School vs All vs Top 10 --%>
              <div class="border border-base-200 overflow-hidden -mx-5">
                <div class="overflow-x-auto">
                  <table class="w-full text-sm">
                    <thead>
                      <tr class="border-b border-base-200 bg-base-50">
                        <th class="text-left px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          Scope
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          Districts
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          Students
                        </th>

                        <th
                          :for={subject <- @crd_comparison.sgp_subjects}
                          class="text-right px-4 py-3 text-xs font-medium text-warning uppercase tracking-wide"
                        >
                          {subject}
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-info uppercase tracking-wide">
                          Avg
                        </th>
                      </tr>
                    </thead>

                    <tbody class="divide-y divide-base-200">
                      <%!-- School (charter) baseline --%>
                      <tr class="border-b-2 border-base-300 bg-info/5">
                        <td class="px-4 py-2.5 font-semibold text-xs text-info">
                          School
                          <span class="block text-base-content/40 font-normal normal-case">
                            {short_name(@crd_comparison.charter_name || @district_code)}
                          </span>
                        </td>

                        <td class="px-4 py-2.5 text-right text-xs text-base-content/30">—</td>

                        <td class="px-4 py-2.5 text-right text-xs text-base-content/30">—</td>

                        <td
                          :for={subject <- @crd_comparison.sgp_subjects}
                          class="px-4 py-2.5 text-right"
                        >
                          <span class={[
                            "font-semibold text-xs",
                            sgp_score_class(Map.get(@crd_comparison.charter_sgp, subject))
                          ]}>
                            {format_index(Map.get(@crd_comparison.charter_sgp, subject))}
                          </span>
                        </td>

                        <td class="px-4 py-2.5 text-right">
                          <span class={[
                            "font-semibold text-xs",
                            sgp_score_class(@crd_comparison.charter_sgp_avg)
                          ]}>
                            {format_index(@crd_comparison.charter_sgp_avg)}
                          </span>
                        </td>
                      </tr>

                      <tr
                        :for={
                          {label, scope, v} <- [
                            {"All", "all", @crd_comparison.all},
                            {"Top 10", "top10", @crd_comparison.top10}
                          ]
                        }
                        class={["hover:bg-base-50", @crd_scope == scope && "bg-warning/5 font-medium"]}
                      >
                        <td class="px-4 py-2.5 font-semibold text-xs">{label}</td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs text-base-content/70">
                          {v.sgp_scored_count}
                        </td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs text-base-content/70">
                          {format_number(v.sgp_total_students)}
                        </td>

                        <td
                          :for={subject <- @crd_comparison.sgp_subjects}
                          class="px-4 py-2.5 text-right"
                        >
                          <span class={[
                            "text-xs",
                            sgp_score_class(Map.get(v.composite_sgp_subjects, subject))
                          ]}>
                            {format_index(Map.get(v.composite_sgp_subjects, subject))}
                          </span>
                        </td>

                        <td class="px-4 py-2.5 text-right">
                          <span class={["text-xs", sgp_score_class(v.composite_sgp_avg)]}>
                            {format_index(v.composite_sgp_avg)}
                          </span>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>

              <%!-- SGP resident district breakdown --%>
              <div class="border border-base-200 overflow-hidden -mx-5 -mb-5">
                <div class="overflow-x-auto">
                  <table class="w-full text-sm">
                    <thead>
                      <tr class="border-b border-base-200 bg-base-50">
                        <th class="text-left px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          Resident District
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          Students
                        </th>

                        <th
                          :for={subject <- @crd_comparison.sgp_subjects}
                          class="text-right px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide"
                        >
                          {subject}
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-info uppercase tracking-wide">
                          Avg
                        </th>
                      </tr>
                    </thead>

                    <tbody class="divide-y divide-base-200">
                      <tr
                        :for={r <- @crd_view.residents}
                        class={["hover:bg-base-50", !r.has_sgp && "opacity-50"]}
                      >
                        <td class="px-4 py-2.5 font-medium text-xs">
                          {r.resident_name}
                          <span :if={!r.has_sgp} class="text-base-content/35 font-normal">
                            (no SGP data)
                          </span>
                        </td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs text-base-content/60">
                          {format_number(r.weight)}
                        </td>

                        <td
                          :for={subject <- @crd_comparison.sgp_subjects}
                          class="px-4 py-2.5 text-right"
                        >
                          <span class={["text-xs", sgp_score_class(Map.get(r.sgp, subject))]}>
                            {format_index(Map.get(r.sgp, subject))}
                          </span>
                        </td>

                        <td class="px-4 py-2.5 text-right">
                          <span class={["text-xs font-semibold", sgp_score_class(r.sgp_avg)]}>
                            {format_index(r.sgp_avg)}
                          </span>
                        </td>
                      </tr>
                    </tbody>

                    <tfoot :if={@crd_view.sgp_scored_count > 0}>
                      <tr class="border-t-2 border-base-300 bg-warning/5 font-semibold">
                        <td class="px-4 py-3 text-xs uppercase tracking-wide text-warning">
                          {crd_scope_label(@crd_scope)} (weighted)
                        </td>

                        <td class="px-4 py-3 text-right tabular-nums text-xs">
                          {format_number(@crd_view.sgp_total_students)}
                        </td>

                        <td
                          :for={subject <- @crd_comparison.sgp_subjects}
                          class="px-4 py-3 text-right"
                        >
                          <span class={[
                            "text-xs",
                            sgp_score_class(Map.get(@crd_view.composite_sgp_subjects, subject))
                          ]}>
                            {format_index(Map.get(@crd_view.composite_sgp_subjects, subject))}
                          </span>
                        </td>

                        <td class="px-4 py-3 text-right">
                          <span class={["text-xs", sgp_score_class(@crd_view.composite_sgp_avg)]}>
                            {format_index(@crd_view.composite_sgp_avg)}
                          </span>
                        </td>
                      </tr>
                    </tfoot>
                  </table>
                </div>
              </div>
            </.collapsible_section>

            <%!-- All Subjects composite --%>
            <.collapsible_section
              :if={@crd_view.scored_count > 0}
              id="all-subjects-avg-crd"
              title="All Subjects Average"
            >
              <.subject_comparison
                subject="All Subjects"
                primary={@crd_comparison.charter_avg}
                primary_label={short_name(@crd_comparison.charter_name || @district_code)}
                compare={@crd_view.composite_avg}
                compare_label={if @crd_scope == "top10", do: "Top 10 CRD", else: "CRD Composite"}
              />
            </.collapsible_section>

            <%!-- M-STEP proficiency by subject --%>
            <.collapsible_section
              :if={@crd_view.scored_count > 0}
              id="mstep-proficiency-crd"
              title="M-STEP Proficiency by Subject"
            >
              <.subject_comparison
                :for={subject <- @subjects}
                subject={subject}
                primary={Map.get(@crd_comparison.charter_subjects, subject)}
                primary_label={short_name(@crd_comparison.charter_name || @district_code)}
                compare={Map.get(@crd_view.composite_subjects, subject)}
                compare_label={if @crd_scope == "top10", do: "Top 10 CRD", else: "CRD Composite"}
              />
            </.collapsible_section>

            <%!-- Resident district breakdown --%>
            <.collapsible_section
              id="resident-breakdown-crd"
              title="Resident Districts — M-STEP Proficiency"
            >
              <:badge>
                <span
                  :if={@crd_scope == "top10"}
                  class="text-xs font-medium text-warning bg-warning/10 px-2 py-0.5"
                >
                  Top 10 by Enrollment
                </span>
              </:badge>
              <div class="border border-base-200 overflow-hidden -mx-5 -mb-5">
                <div class="overflow-x-auto">
                  <table class="w-full text-sm">
                    <thead>
                      <tr class="border-b border-base-200 bg-base-50">
                        <th class="text-left px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          District
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          Students
                        </th>

                        <th
                          :for={subject <- @subjects}
                          class="text-right px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide"
                        >
                          {short_name(subject)}
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-info uppercase tracking-wide">
                          Avg
                        </th>
                      </tr>
                    </thead>

                    <tbody class="divide-y divide-base-200">
                      <tr
                        :for={r <- @crd_view.residents}
                        class={["hover:bg-base-50", !r.has_data && "opacity-50"]}
                      >
                        <td class="px-4 py-2.5 font-medium text-xs">
                          {r.resident_name}
                          <span :if={!r.has_data} class="text-base-content/35 font-normal">
                            (no M-STEP data)
                          </span>
                        </td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs text-base-content/60">
                          {format_number(r.weight)}
                        </td>

                        <td :for={subject <- @subjects} class="px-4 py-2.5 text-right">
                          <.pct_badge value={Map.get(r.subjects, subject)} color="warning" />
                        </td>

                        <td class="px-4 py-2.5 text-right">
                          <.pct_badge value={r.avg} color="info" />
                        </td>
                      </tr>
                    </tbody>

                    <tfoot :if={@crd_view.scored_count > 0}>
                      <tr class="border-t-2 border-base-300 bg-warning/5 font-semibold">
                        <td class="px-4 py-3 text-xs uppercase tracking-wide text-warning">
                          {if @crd_scope == "top10",
                            do: "Top 10 CRD Composite (weighted)",
                            else: "CRD Composite (weighted)"}
                        </td>

                        <td class="px-4 py-3 text-right tabular-nums text-xs">
                          {format_number(@crd_view.total_students)}
                        </td>

                        <td :for={subject <- @subjects} class="px-4 py-3 text-right">
                          <.pct_badge
                            value={Map.get(@crd_view.composite_subjects, subject)}
                            color="warning"
                          />
                        </td>

                        <td class="px-4 py-3 text-right">
                          <.pct_badge value={@crd_view.composite_avg} color="info" />
                        </td>
                      </tr>
                    </tfoot>
                  </table>
                </div>
              </div>
            </.collapsible_section>

            <%!-- ───────────────────── SAT comparison ───────────────────── --%>
            <.collapsible_section
              :if={@crd_comparison.has_any_sat}
              id="sat-comparison-crd"
              title="SAT College Readiness"
            >
              <:badge>
                <span :if={@crd_scope == "top10"} class="badge badge-warning badge-xs">Top 10</span>
              </:badge>
              <%!-- SAT summary table: School vs All vs Top 10 --%>
              <div class="border border-base-200 overflow-hidden -mx-5">
                <div class="overflow-x-auto">
                  <table class="w-full text-sm">
                    <thead>
                      <tr class="border-b border-base-200 bg-base-50">
                        <th class="text-left px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          Scope
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          Districts
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          Students
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-info uppercase tracking-wide">
                          Math
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-success uppercase tracking-wide">
                          EBRW
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-warning uppercase tracking-wide">
                          All
                        </th>
                      </tr>
                    </thead>

                    <tbody class="divide-y divide-base-200">
                      <%!-- School (charter) baseline --%>
                      <tr class="border-b-2 border-base-300 bg-info/5">
                        <td class="px-4 py-2.5 font-semibold text-xs text-info">
                          School
                          <span class="block text-base-content/40 font-normal normal-case">
                            {short_name(@crd_comparison.charter_name || @district_code)}
                          </span>
                        </td>

                        <td class="px-4 py-2.5 text-right text-xs text-base-content/30">—</td>

                        <td class="px-4 py-2.5 text-right text-xs text-base-content/30">—</td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs font-semibold">
                          {fmt_sat(@crd_comparison.charter_sat && @crd_comparison.charter_sat.math)}
                        </td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs font-semibold">
                          {fmt_sat(@crd_comparison.charter_sat && @crd_comparison.charter_sat.ebrw)}
                        </td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs font-semibold">
                          {fmt_sat(@crd_comparison.charter_sat && @crd_comparison.charter_sat.all)}
                        </td>
                      </tr>

                      <tr
                        :for={
                          {label, scope, v} <- [
                            {"All", "all", @crd_comparison.all},
                            {"Top 10", "top10", @crd_comparison.top10}
                          ]
                        }
                        class={["hover:bg-base-50", @crd_scope == scope && "bg-warning/5 font-medium"]}
                      >
                        <td class="px-4 py-2.5 font-semibold text-xs">{label}</td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs text-base-content/70">
                          {v.sat_scored_count}
                        </td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs text-base-content/70">
                          {format_number(v.sat_total_students)}
                        </td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs">
                          {fmt_sat(v.sat_composite.math)}
                        </td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs">
                          {fmt_sat(v.sat_composite.ebrw)}
                        </td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs">
                          {fmt_sat(v.sat_composite.all)}
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
              <%!-- SAT score bars: charter vs composite --%>
              <div
                :if={@crd_view.sat_scored_count > 0}
                class="bg-base-100 border border-base-200 p-5 space-y-5"
              >
                <.sat_score_bar
                  subject="Math Score"
                  score={@crd_comparison.charter_sat && @crd_comparison.charter_sat.math}
                  compare={@crd_view.sat_composite.math}
                  compare_label={crd_scope_label(@crd_scope)}
                  max={800}
                  label={short_name(@crd_comparison.charter_name || @district_code)}
                />
                <.sat_score_bar
                  subject="EBRW Score"
                  score={@crd_comparison.charter_sat && @crd_comparison.charter_sat.ebrw}
                  compare={@crd_view.sat_composite.ebrw}
                  compare_label={crd_scope_label(@crd_scope)}
                  max={800}
                  label={short_name(@crd_comparison.charter_name || @district_code)}
                />
                <.sat_score_bar
                  subject="All Score"
                  score={@crd_comparison.charter_sat && @crd_comparison.charter_sat.all}
                  compare={@crd_view.sat_composite.all}
                  compare_label={crd_scope_label(@crd_scope)}
                  max={1600}
                  label={short_name(@crd_comparison.charter_name || @district_code)}
                />
              </div>
              <%!-- SAT resident district breakdown --%>
              <div class="bg-base-100 border border-base-200 overflow-hidden">
                <div class="overflow-x-auto">
                  <table class="w-full text-sm">
                    <thead>
                      <tr class="border-b border-base-200 bg-base-50">
                        <th class="text-left px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          Resident District
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          Students
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-info uppercase tracking-wide">
                          Math
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-success uppercase tracking-wide">
                          EBRW
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-warning uppercase tracking-wide">
                          All
                        </th>
                      </tr>
                    </thead>

                    <tbody class="divide-y divide-base-200">
                      <tr
                        :for={r <- @crd_view.residents}
                        class={["hover:bg-base-50", !r.has_sat && "opacity-50"]}
                      >
                        <td class="px-4 py-2.5 font-medium text-xs">
                          {r.resident_name}
                          <span :if={!r.has_sat} class="text-base-content/35 font-normal">
                            (no SAT data)
                          </span>
                        </td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs text-base-content/60">
                          {format_number(r.weight)}
                        </td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs">
                          {fmt_sat(r.sat && r.sat.math)}
                        </td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs">
                          {fmt_sat(r.sat && r.sat.ebrw)}
                        </td>

                        <td class="px-4 py-2.5 text-right tabular-nums text-xs">
                          {fmt_sat(r.sat && r.sat.all)}
                        </td>
                      </tr>
                    </tbody>

                    <tfoot :if={@crd_view.sat_scored_count > 0}>
                      <tr class="border-t-2 border-base-300 bg-warning/5 font-semibold">
                        <td class="px-4 py-3 text-xs uppercase tracking-wide text-warning">
                          {crd_scope_label(@crd_scope)} (weighted)
                        </td>

                        <td class="px-4 py-3 text-right tabular-nums text-xs">
                          {format_number(@crd_view.sat_total_students)}
                        </td>

                        <td class="px-4 py-3 text-right tabular-nums text-xs">
                          {fmt_sat(@crd_view.sat_composite.math)}
                        </td>

                        <td class="px-4 py-3 text-right tabular-nums text-xs">
                          {fmt_sat(@crd_view.sat_composite.ebrw)}
                        </td>

                        <td class="px-4 py-3 text-right tabular-nums text-xs">
                          {fmt_sat(@crd_view.sat_composite.all)}
                        </td>
                      </tr>
                    </tfoot>
                  </table>
                </div>
              </div>
            </.collapsible_section>
          </div>
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

          <%!-- ── Student Growth Percentile (SGP) ─────────────────────────────────── --%>
          <% dc_sgp_comparison = sgp_comparison_rows(@primary_sgp, @compare_sgp) %>
          <% dc_sgp_visible_subjects =
            Enum.filter(
              dc_sgp_comparison.subjects,
              &sgp_subject_selected?(&1, @sgp_subject_filter)
            ) %>
          <% dc_sgp_primary_all_grades = sgp_all_grades_by_subject(@primary_sgp) %>
          <% dc_sgp_compare_all_grades = sgp_all_grades_by_subject(@compare_sgp) %>

          <%!-- SGP by Subject — all grades combined --%>
          <.collapsible_section
            :if={@primary && dc_sgp_visible_subjects != []}
            id="sgp-bars-district-comparison"
            title="Student Growth Percentile by Subject"
          >
            <:badge>
              <span class="text-xs text-base-content/40 normal-case font-normal">
                Dashed line = 50th percentile (typical growth)
              </span>
            </:badge>
            <.sgp_subject_bar
              :for={subject <- dc_sgp_visible_subjects}
              subject={subject}
              primary={Map.get(dc_sgp_primary_all_grades, subject)}
              primary_label={short_name(@primary.district_name)}
              compare={@compare && Map.get(dc_sgp_compare_all_grades, subject)}
              compare_label={@compare && short_name(@compare.district_name)}
            />
          </.collapsible_section>

          <%!-- SGP by Grade --%>
          <.collapsible_section
            :if={@primary && dc_sgp_comparison.grades != []}
            id="sgp-table-district-comparison"
            title="Student Growth Percentile"
          >
            <%!-- Subject filter --%>
            <div class="flex items-center gap-2 flex-wrap -mx-5 -mt-1 px-5 py-3 border-b border-base-200 bg-base-50/50">
              <span class="text-xs font-medium text-base-content/40 uppercase tracking-wide">
                Subjects
              </span>
              <button
                :for={subject <- dc_sgp_comparison.subjects}
                type="button"
                phx-click="toggle_sgp_subject"
                phx-value-subject={subject}
                class={[
                  "badge badge-sm cursor-pointer transition-colors",
                  if(sgp_subject_selected?(subject, @sgp_subject_filter),
                    do: "badge-secondary",
                    else: "badge-outline text-base-content/40"
                  )
                ]}
              >
                {subject}
              </button>
              <button
                :if={@sgp_subject_filter != nil}
                type="button"
                phx-click="reset_sgp_subject_filter"
                class="text-xs text-base-content/40 hover:text-base-content underline ml-1"
              >
                Show all
              </button>
            </div>

            <div
              :if={dc_sgp_visible_subjects == []}
              class="px-5 py-8 text-center text-xs text-base-content/30 italic"
            >
              No subjects selected — choose at least one above.
            </div>

            <div :if={dc_sgp_visible_subjects != []} class="overflow-x-auto -mx-5 -mb-5">
              <table class="table table-sm w-full">
                <thead>
                  <tr class="text-xs text-base-content/50 border-b border-base-200">
                    <th class="px-4 py-2 font-medium text-left">Grade</th>
                    <%= for subject <- dc_sgp_visible_subjects do %>
                      <th class="px-4 py-2 font-medium text-right text-info">
                        {subject} — {short_name(@primary.district_name)}
                      </th>
                      <th :if={@compare} class="px-4 py-2 font-medium text-right text-warning">
                        {subject} — {short_name(@compare.district_name)}
                      </th>
                    <% end %>
                  </tr>
                </thead>

                <tbody class="divide-y divide-base-200">
                  <tr :for={g <- dc_sgp_comparison.grades} class="hover:bg-base-50">
                    <td class="px-4 py-2 font-medium">{g.grade}</td>
                    <%= for subject <- dc_sgp_visible_subjects do %>
                      <% pair = Map.get(g.by_subject, subject) %>
                      <td class="px-4 py-2 text-right tabular-nums">
                        <span class={[
                          "font-semibold",
                          sgp_score_class(pair.primary && pair.primary.mean_sgp)
                        ]}>
                          {if pair.primary && pair.primary.mean_sgp,
                            do: format_index(pair.primary.mean_sgp),
                            else: "—"}
                        </span>
                      </td>
                      <td :if={@compare} class="px-4 py-2 text-right tabular-nums">
                        <span class={[
                          "font-semibold",
                          sgp_score_class(pair.compare && pair.compare.mean_sgp)
                        ]}>
                          {if pair.compare && pair.compare.mean_sgp,
                            do: format_index(pair.compare.mean_sgp),
                            else: "—"}
                        </span>
                      </td>
                    <% end %>
                  </tr>
                </tbody>
              </table>
            </div>
          </.collapsible_section>

          <%!-- ── Subject Proficiency Side-by-Side ──────────────────────────────── --%>
          <.collapsible_section
            :if={@primary}
            id="mstep-proficiency-district-comparison"
            title="M-STEP Proficiency by Subject"
          >
            <.subject_comparison
              :for={subject <- @subjects}
              subject={subject}
              primary={Map.get(@primary.all_subjects, subject)}
              primary_label={short_name(@primary.district_name)}
              compare={@compare && Map.get(@compare.all_subjects, subject)}
              compare_label={@compare && short_name(@compare.district_name)}
            />
          </.collapsible_section>

          <%!-- ── Grade Breakdown ─────────────────────────────────────────────────── --%>
          <.collapsible_section
            :if={@primary && @primary.grade_breakdown != []}
            id="grade-breakdown-district-comparison"
            title="Grade-Level Breakdown — ELA & Math"
          >
            <div class="border border-base-200 overflow-hidden -mx-5 -mb-5">
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
          </.collapsible_section>

          <%!-- ── Proficiency Distribution ───────────────────────────────────────── --%>
          <.collapsible_section
            :if={@primary && @primary.proficiency_dist}
            id="proficiency-dist-district-comparison"
            title="Proficiency Level Distribution — All M-STEP Subjects"
          >
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
          </.collapsible_section>
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
                  <%!-- Enrollment breakdown --%>
                  <div :if={@enrollment} class="pt-4 mt-3 border-t border-base-200">
                    <div class="text-xs font-semibold uppercase tracking-wider text-base-content/40 mb-3">
                      Enrollment — {@selected_year}
                    </div>

                    <.enrollment_donut
                      total={@enrollment.total_enrollment}
                      econ_disadvantaged={@enrollment.economic_disadvantaged_enrollment}
                    />
                  </div>

                  <div :if={is_nil(@enrollment)} class="pt-2 mt-1 text-xs text-base-content/30 italic">
                    No enrollment data for this year
                  </div>
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
                  <%!-- LEA Enrollment breakdown --%>
                  <div :if={@lea_enrollment} class="pt-4 mt-3 border-t border-base-200">
                    <div class="text-xs font-semibold uppercase tracking-wider text-base-content/40 mb-3">
                      Enrollment — {@selected_year}
                    </div>

                    <.enrollment_donut
                      total={@lea_enrollment.total_enrollment}
                      econ_disadvantaged={@lea_enrollment.economic_disadvantaged_enrollment}
                    />
                  </div>

                  <div
                    :if={is_nil(@lea_enrollment)}
                    class="pt-2 mt-1 text-xs text-base-content/30 italic"
                  >
                    No enrollment data for this year
                  </div>
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
            <%!-- School Index Score --%>
            <.collapsible_section
              :if={@school_index}
              id="school-index-score"
              title="School Index Score"
            >
              <:badge>
                <span
                  :if={Map.get(@index_thresholds, :overall)}
                  class="text-xs text-base-content/40 normal-case font-normal"
                >
                  Bottom 5% Threshold [{format_index(Map.get(@index_thresholds, :overall))}]
                </span>
              </:badge>
              <:trailing>
                <div class="flex items-baseline gap-1.5">
                  <span class={"text-xl font-black tabular-nums #{overall_score_class(@school_index.overall_index, Map.get(@index_thresholds, :overall))}"}>
                    {format_index(@school_index.overall_index)}
                  </span>
                  <span class="text-xs text-base-content/40 font-medium">/ 100</span>
                </div>
              </:trailing>
              <%!-- Sub-index rows --%>
              <div class="divide-y divide-base-200 -mx-5">
                <.index_row
                  label="Growth"
                  value={@school_index.growth_index}
                  threshold={Map.get(@index_thresholds, :growth)}
                />
                <.index_row
                  label="Proficiency"
                  value={@school_index.proficiency_index}
                  threshold={Map.get(@index_thresholds, :proficiency)}
                />
                <.index_row
                  label="Graduation"
                  value={@school_index.graduation_index}
                  threshold={Map.get(@index_thresholds, :graduation)}
                />
                <.index_row
                  label="EL Progress"
                  value={@school_index.el_progress_index}
                  threshold={Map.get(@index_thresholds, :el_progress)}
                />
                <.index_row
                  label="School Quality"
                  value={@school_index.school_quality_index}
                  threshold={Map.get(@index_thresholds, :school_quality)}
                />
                <.index_row
                  label="Subject Participation"
                  value={@school_index.subject_participation_index}
                  threshold={Map.get(@index_thresholds, :subject_participation)}
                />
                <.index_row
                  label="EL Participation"
                  value={@school_index.el_participation_index}
                  threshold={Map.get(@index_thresholds, :el_participation)}
                />
              </div>
              <%!-- Support category footer --%>
              <div
                :if={@school_index.support_category_name}
                class="flex items-start gap-3 -mx-5 -mb-5 px-5 py-3 bg-warning/5 border-t border-warning/20"
              >
                <.icon name="hero-flag" class="size-3.5 text-warning shrink-0 mt-0.5" />
                <div>
                  <span class="badge badge-warning badge-sm">
                    {@school_index.support_category_name}
                  </span>
                  <p
                    :if={@school_index.support_category_reason}
                    class="text-xs text-base-content/50 mt-0.5"
                  >
                    {@school_index.support_category_reason}
                  </p>
                </div>
              </div>
            </.collapsible_section>

            <%!-- Student Growth Percentile (SGP) — school vs. LEA --%> <% sgp_comparison =
              sgp_comparison_rows(@sgp_results, @sgp_lea_result) %> <% sgp_visible_subjects =
              Enum.filter(
                sgp_comparison.subjects,
                &sgp_subject_selected?(&1, @sgp_subject_filter)
              ) %> <% sgp_school_all_grades = sgp_all_grades_by_subject(@sgp_results) %> <% sgp_lea_all_grades =
              sgp_all_grades_by_subject(@sgp_lea_result) %>
            <%!-- SGP by Subject — all grades combined --%>
            <.collapsible_section
              :if={sgp_visible_subjects != []}
              id="sgp-bars-school-vs-lea"
              title="Student Growth Percentile by Subject"
            >
              <:badge>
                <span class="text-xs text-base-content/40 normal-case font-normal">
                  Dashed line = 50th percentile (typical growth)
                </span>
              </:badge>
              <.sgp_subject_bar
                :for={subject <- sgp_visible_subjects}
                subject={subject}
                primary={Map.get(sgp_school_all_grades, subject)}
                primary_label={short_name(@school_vs_lea.school_name)}
                compare={Map.get(sgp_lea_all_grades, subject)}
                compare_label={
                  short_name(
                    @school_vs_lea.lea_district_name || @school_vs_lea.lea_district_code ||
                      "LEA"
                  )
                }
              />
            </.collapsible_section>

            <.collapsible_section
              :if={sgp_comparison.grades != []}
              id="sgp-table-school-vs-lea"
              title="Student Growth Percentile — School vs. LEA"
            >
              <:badge>
                <span class="text-xs text-base-content/40 normal-case font-normal">
                  Dashed line = 50th percentile (typical growth)
                </span>
              </:badge>
              <%!-- Subject filter --%>
              <div class="flex items-center gap-2 flex-wrap -mx-5 -mt-1 px-5 py-3 border-b border-base-200 bg-base-50/50">
                <span class="text-xs font-medium text-base-content/40 uppercase tracking-wide">
                  Subjects
                </span>
                <button
                  :for={subject <- sgp_comparison.subjects}
                  type="button"
                  phx-click="toggle_sgp_subject"
                  phx-value-subject={subject}
                  class={[
                    "badge badge-sm cursor-pointer transition-colors",
                    if(sgp_subject_selected?(subject, @sgp_subject_filter),
                      do: "badge-secondary",
                      else: "badge-outline text-base-content/40"
                    )
                  ]}
                >
                  {subject}
                </button>
                <button
                  :if={@sgp_subject_filter != nil}
                  type="button"
                  phx-click="reset_sgp_subject_filter"
                  class="text-xs text-base-content/40 hover:text-base-content underline ml-1"
                >
                  Show all
                </button>
              </div>

              <div
                :if={sgp_visible_subjects == []}
                class="px-5 py-8 text-center text-xs text-base-content/30 italic"
              >
                No subjects selected — choose at least one above.
              </div>

              <div :if={sgp_visible_subjects != []} class="overflow-x-auto -mx-5 -mb-5">
                <table class="table table-sm w-full">
                  <thead>
                    <tr class="text-xs text-base-content/50 border-b border-base-200">
                      <th class="px-4 py-2 font-medium text-left">Grade</th>
                      <%= for subject <- sgp_visible_subjects do %>
                        <th class="px-4 py-2 font-medium text-right text-info">
                          {subject} — School
                        </th>
                        <th class="px-4 py-2 font-medium text-right text-warning">
                          {subject} — LEA
                        </th>
                      <% end %>
                    </tr>
                  </thead>

                  <tbody class="divide-y divide-base-200">
                    <tr :for={g <- sgp_comparison.grades} class="hover:bg-base-50">
                      <td class="px-4 py-2 font-medium">{g.grade}</td>
                      <%= for subject <- sgp_visible_subjects do %>
                        <% pair = Map.get(g.by_subject, subject) %>
                        <td class="px-4 py-2 text-right tabular-nums">
                          <span class={[
                            "font-semibold",
                            sgp_score_class(pair.primary && pair.primary.mean_sgp)
                          ]}>
                            {if pair.primary && pair.primary.mean_sgp,
                              do: format_index(pair.primary.mean_sgp),
                              else: "—"}
                          </span>
                        </td>
                        <td class="px-4 py-2 text-right tabular-nums">
                          <span class={[
                            "font-semibold",
                            sgp_score_class(pair.compare && pair.compare.mean_sgp)
                          ]}>
                            {if pair.compare && pair.compare.mean_sgp,
                              do: format_index(pair.compare.mean_sgp),
                              else: "—"}
                          </span>
                        </td>
                      <% end %>
                    </tr>
                  </tbody>
                </table>
              </div>
            </.collapsible_section>

            <div
              :if={sgp_comparison.grades == [] && !@school_vs_lea.no_results}
              class="bg-base-50 border border-dashed border-base-300 px-5 py-4 text-xs text-base-content/30 italic"
            >
              No Student Growth Percentile data found for this school in {@selected_year}.
            </div>
            <%!-- All Subjects Average --%>
            <.collapsible_section
              :if={!@school_vs_lea.no_results && !@school_vs_lea.no_lea_found}
              id="all-subjects-avg-school-vs-lea"
              title="All Subjects Average"
            >
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
            </.collapsible_section>

            <%!-- Subject proficiency comparison --%>
            <.collapsible_section
              :if={!@school_vs_lea.no_results && !@school_vs_lea.no_lea_found}
              id="mstep-proficiency-school-vs-lea"
              title="M-STEP Proficiency by Subject"
            >
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
            </.collapsible_section>

            <%!-- Grade breakdown --%>
            <.collapsible_section
              :if={
                !@school_vs_lea.no_results && !@school_vs_lea.no_lea_found &&
                  @school_vs_lea.grade_breakdown != []
              }
              id="grade-breakdown-school-vs-lea"
              title="Grade-Level Breakdown — ELA & Math"
            >
              <div class="border border-base-200 overflow-hidden -mx-5 -mb-5">
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
                          <.pct_badge
                            value={row.school_ela}
                            color="info"
                            suppressed={row.school_ela_suppressed}
                            approximate={row.school_ela_approximate}
                          />
                        </td>

                        <td class="px-4 py-2.5 text-right">
                          <.pct_badge value={row.lea_ela} color="warning" />
                        </td>

                        <td class="px-4 py-2.5 text-right">
                          <.pct_badge value={row.state_ela} color="success" />
                        </td>

                        <td class="px-4 py-2.5 text-right">
                          <.pct_badge
                            value={row.school_math}
                            color="info"
                            suppressed={row.school_math_suppressed}
                            approximate={row.school_math_approximate}
                          />
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
            </.collapsible_section>

            <%!-- Grade breakdown — Economically Disadvantaged --%>
            <.collapsible_section
              :if={@econ_grade_breakdown != []}
              id="grade-breakdown-econ-school-vs-lea"
              title="Grade-Level Breakdown — ELA & Math"
            >
              <:badge>
                <span class="text-xs font-medium text-warning bg-warning/10 px-2 py-0.5">
                  Economically Disadvantaged
                </span>
              </:badge>
              <div class="border border-base-200 overflow-hidden -mx-5 -mb-5">
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
                      <tr :for={row <- @econ_grade_breakdown} class="hover:bg-base-50">
                        <td class="px-4 py-2.5 font-medium text-xs">{grade_label(row.grade)}</td>

                        <td class="px-4 py-2.5 text-right">
                          <.pct_badge
                            value={row.school_ela}
                            color="info"
                            suppressed={row.school_ela_suppressed}
                            approximate={row.school_ela_approximate}
                          />
                        </td>

                        <td class="px-4 py-2.5 text-right">
                          <.pct_badge value={row.lea_ela} color="warning" />
                        </td>

                        <td class="px-4 py-2.5 text-right">
                          <.pct_badge value={row.state_ela} color="success" />
                        </td>

                        <td class="px-4 py-2.5 text-right">
                          <.pct_badge
                            value={row.school_math}
                            color="info"
                            suppressed={row.school_math_suppressed}
                            approximate={row.school_math_approximate}
                          />
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
            </.collapsible_section>

            <%!-- SAT By Subject --%>
            <.collapsible_section
              :if={@sat_results != []}
              id="sat-by-subject-school-vs-lea"
              title="SAT College Readiness by Subject"
            >
              <% sat_all = Enum.find(@sat_results, &(&1.subgroup == "All Students")) %> <% lea_label =
                short_name(
                  @school_vs_lea.lea_district_name || @school_vs_lea.lea_district_code || "LEA"
                ) %>
              <.sat_score_bar
                subject="Math Score"
                score={sat_all && sat_all.math_score_average}
                compare={@sat_lea_result && @sat_lea_result.math_score_average}
                compare_label={@sat_lea_result && lea_label}
                state={@sat_state_result && @sat_state_result.math_score_average}
                max={800}
                label={short_name(@school_vs_lea.school_name)}
              />
              <.sat_score_bar
                subject="EBRW Score"
                score={sat_all && sat_all.ebrw_score_average}
                compare={@sat_lea_result && @sat_lea_result.ebrw_score_average}
                compare_label={@sat_lea_result && lea_label}
                state={@sat_state_result && @sat_state_result.ebrw_score_average}
                max={800}
                label={short_name(@school_vs_lea.school_name)}
              />
              <.sat_score_bar
                subject="All Score"
                score={sat_all && sat_all.all_subject_score_average}
                compare={@sat_lea_result && @sat_lea_result.all_subject_score_average}
                compare_label={@sat_lea_result && lea_label}
                state={@sat_state_result && @sat_state_result.all_subject_score_average}
                max={1600}
                label={short_name(@school_vs_lea.school_name)}
              />
            </.collapsible_section>

            <%!-- SAT College Readiness by Subgroup --%>
            <.collapsible_section
              :if={@sat_results != []}
              id="sat-by-subgroup-school-vs-lea"
              title="SAT College Readiness by Subgroup"
            >
              <div class="border border-base-200 overflow-hidden -mx-5 -mb-5">
                <div class="overflow-x-auto">
                  <table class="w-full text-sm">
                    <thead>
                      <tr class="border-b border-base-200 bg-base-50">
                        <th class="text-left px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          Subgroup
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                          Assessed
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-info uppercase tracking-wide">
                          Math Score
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-success uppercase tracking-wide">
                          EBRW Score
                        </th>

                        <th class="text-right px-4 py-3 text-xs font-medium text-warning uppercase tracking-wide">
                          All Score
                        </th>
                      </tr>
                    </thead>

                    <tbody class="divide-y divide-base-200">
                      <tr
                        :for={
                          row <-
                            Enum.filter(
                              @sat_results,
                              &(&1.subgroup in [
                                  "All Students",
                                  "Economically Disadvantaged"
                                ])
                            )
                        }
                        class="hover:bg-base-50"
                      >
                        <td class="px-4 py-2.5 font-medium text-xs">
                          {row.subgroup || "All Students"}
                        </td>

                        <td class="px-4 py-2.5 text-right text-xs text-base-content/60">
                          {if row.math_num_assessed,
                            do: format_number(row.math_num_assessed),
                            else: "—"}
                        </td>

                        <td class="px-4 py-2.5 text-right text-xs font-semibold tabular-nums text-info">
                          {if row.math_score_average,
                            do: Decimal.round(row.math_score_average, 2),
                            else: "—"}
                        </td>

                        <td class="px-4 py-2.5 text-right text-xs font-semibold tabular-nums text-success">
                          {if row.ebrw_score_average,
                            do: Decimal.round(row.ebrw_score_average, 2),
                            else: "—"}
                        </td>

                        <td class="px-4 py-2.5 text-right text-xs font-semibold tabular-nums text-warning">
                          {if row.all_subject_score_average,
                            do: Decimal.round(row.all_subject_score_average, 2),
                            else: "—"}
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </.collapsible_section>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Collapsible section. Used to keep the long per-tab data pages condensed.
  #
  # Deliberately NOT a native <details>/<summary> — that toggles via plain
  # browser behavior, which LiveView's DOM patching doesn't know about. Any
  # server round-trip that touches this subtree (e.g. clicking a subject
  # filter inside it) gets morphdom-reconciled against the freshly rendered
  # HTML and silently re-closes it. `Phoenix.LiveView.JS` commands are
  # specifically protected from that reconciliation, so the toggle is done
  # entirely client-side via JS.toggle/JS.toggle_class — no server round trip,
  # and it survives any later patch to the content inside it.
  # ---------------------------------------------------------------------------

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :open, :boolean, default: false
  slot :badge
  slot :trailing
  slot :inner_block, required: true

  def collapsible_section(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-200">
      <button
        type="button"
        phx-click={
          JS.toggle(to: "##{@id}-content")
          |> JS.toggle_class("rotate-90", to: "##{@id}-chevron")
        }
        class="w-full flex items-center gap-2 px-5 py-3 cursor-pointer select-none text-left hover:bg-base-50 transition-colors"
      >
        <span
          id={"#{@id}-chevron"}
          class={["inline-block shrink-0 transition-transform duration-200", @open && "rotate-90"]}
        >
          <.icon name="hero-chevron-right" class="size-3.5 text-base-content/40" />
        </span>
        <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60">
          {@title}
        </h2>
        {render_slot(@badge)}
        <div class="flex-1 h-px bg-base-200"></div>
        {render_slot(@trailing)}
      </button>
      <div
        id={"#{@id}-content"}
        class={[
          "px-5 pb-5 pt-1 border-t border-base-200 space-y-4",
          !@open && "hidden"
        ]}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Enrollment donut chart component
  # ---------------------------------------------------------------------------

  attr :total, :integer, default: nil
  attr :econ_disadvantaged, :integer, default: nil

  def enrollment_donut(assigns) do
    total = assigns.total || 0

    econ_pct =
      if total > 0 && is_integer(assigns.econ_disadvantaged) do
        Float.round(assigns.econ_disadvantaged / total * 100, 1)
      else
        0.0
      end

    assigns =
      assigns
      |> assign(:econ_pct, econ_pct)
      # Econ segment starts at top (-90°), remaining (non-econ) starts where it ends
      |> assign(:non_econ_rotation, -90 + econ_pct * 3.6)

    ~H"""
    <div class="flex items-center gap-4">
      <%!-- SVG donut — r=15.9155 gives circumference≈100, so dasharray values = percentages --%>
      <div class="shrink-0">
        <svg viewBox="0 0 36 36" width="88" height="88">
          <%!-- Background ring --%>
          <circle cx="18" cy="18" r="15.9155" fill="none" stroke="#e5e7eb" stroke-width="3.5" />
          <%!-- Econ disadvantaged segment (amber), starts at top (rotate -90°) --%>
          <circle
            :if={@econ_pct > 0}
            cx="18"
            cy="18"
            r="15.9155"
            fill="none"
            stroke="#f59e0b"
            stroke-width="3.5"
            stroke-dasharray={"#{@econ_pct} #{100 - @econ_pct}"}
            transform="rotate(-90 18 18)"
          /> <%!-- Remaining (non-econ) segment (blue), starts where econ ends --%>
          <circle
            :if={@econ_pct < 100}
            cx="18"
            cy="18"
            r="15.9155"
            fill="none"
            stroke="#3b82f6"
            stroke-width="3.5"
            stroke-dasharray={"#{100 - @econ_pct} #{@econ_pct}"}
            transform={"rotate(#{@non_econ_rotation} 18 18)"}
          /> <%!-- Center label --%>
          <text
            x="18"
            y="16"
            text-anchor="middle"
            font-size="4.5"
            fill="#9ca3af"
            font-family="ui-sans-serif,system-ui,sans-serif"
          >
            Total
          </text>

          <text
            x="18"
            y="22.5"
            text-anchor="middle"
            font-size="5.5"
            font-weight="bold"
            fill="#1f2937"
            font-family="ui-sans-serif,system-ui,sans-serif"
          >
            {if @total, do: format_number(@total), else: "—"}
          </text>
        </svg>
      </div>
      <%!-- Legend --%>
      <div class="space-y-2">
        <div class="flex items-center gap-2 text-xs">
          <span class="inline-block size-2.5 rounded-sm shrink-0" style="background:#3b82f6"></span>
          <span class="text-base-content/60">All Students</span>
          <span class="font-semibold tabular-nums">
            {if @total, do: format_number(@total), else: "—"}
          </span>
        </div>

        <div class="flex items-center gap-2 text-xs">
          <span class="inline-block size-2.5 rounded-sm shrink-0" style="background:#f59e0b"></span>
          <span class="text-base-content/60">Econ. Disadvantaged</span>
          <span class="font-semibold tabular-nums">
            {if @econ_disadvantaged, do: format_number(@econ_disadvantaged), else: "—"}
          </span>
          <span :if={@econ_pct > 0} class="text-base-content/40">({@econ_pct}%)</span>
        </div>
      </div>
    </div>
    """
  end

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
          <.icon name="hero-map-pin" class="size-3" /> {@district.isd_name} ISD
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

  attr :label, :string, required: true
  attr :value, :any, default: nil
  attr :threshold, :any, default: nil

  def index_row(assigns) do
    pct =
      case assigns.value do
        nil -> 0
        d -> d |> Decimal.to_float() |> min(100.0) |> max(0.0)
      end

    score_class =
      cond do
        is_nil(assigns.value) or is_nil(assigns.threshold) -> "text-base-content/70"
        Decimal.compare(assigns.value, assigns.threshold) == :lt -> "text-error"
        true -> "text-success"
      end

    bar_class =
      cond do
        is_nil(assigns.value) or is_nil(assigns.threshold) -> "bg-primary/60"
        Decimal.compare(assigns.value, assigns.threshold) == :lt -> "bg-error/60"
        true -> "bg-success/60"
      end

    threshold_pct =
      case assigns.threshold do
        nil -> nil
        d -> d |> Decimal.to_float() |> min(99.5) |> max(0.0)
      end

    assigns =
      assigns
      |> assign(:pct, pct)
      |> assign(:score_class, score_class)
      |> assign(:bar_class, bar_class)
      |> assign(:threshold_pct, threshold_pct)

    ~H"""
    <div class="flex items-center gap-4 px-5 py-2.5">
      <span class="text-xs text-base-content/50 w-36 shrink-0">{@label}</span>
      <div class="flex-1 bg-base-200 h-2 relative overflow-hidden">
        <div
          class={"absolute inset-y-0 left-0 transition-all duration-500 #{@bar_class}"}
          style={"width: #{@pct}%"}
        >
        </div>

        <div
          :if={@threshold_pct}
          class="absolute top-0 bottom-0 w-0.5 bg-base-content/40"
          style={"left: #{@threshold_pct}%"}
          title={"Threshold: #{format_index(@threshold)}"}
        >
        </div>
      </div>

      <span class={"text-xs font-semibold tabular-nums w-10 text-right #{@score_class}"}>
        {format_index(@value)}
      </span>
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
        <span class="text-xs text-base-content/40 w-20 truncate text-right">{@primary_label}</span>
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
        <span class="text-xs text-base-content/40 w-20 truncate text-right">{@compare_label}</span>
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
        <span class="text-xs text-base-content/40 w-20 truncate text-right">{@state_label}</span>
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
          if @primary_f && @compare_f, do: Float.round(@primary_f - @compare_f, 1), else: nil %> <% delta_state =
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

  attr :subject, :string, required: true
  attr :score, :any, default: nil
  attr :compare, :any, default: nil
  attr :compare_label, :string, default: nil
  attr :state, :any, default: nil
  attr :state_label, :string, default: "State Avg"
  attr :max, :integer, required: true
  attr :label, :string, default: ""

  def sat_score_bar(assigns) do
    score_f = if assigns.score, do: Decimal.to_float(assigns.score), else: nil
    compare_f = if assigns.compare, do: Decimal.to_float(assigns.compare), else: nil
    state_f = if assigns.state, do: Decimal.to_float(assigns.state), else: nil
    pct = if score_f, do: Float.round(score_f / assigns.max * 100, 4), else: 0.0
    compare_pct = if compare_f, do: Float.round(compare_f / assigns.max * 100, 4), else: nil
    state_pct = if state_f, do: Float.round(state_f / assigns.max * 100, 4), else: nil

    assigns =
      assigns
      |> assign(:score_f, score_f)
      |> assign(:compare_f, compare_f)
      |> assign(:state_f, state_f)
      |> assign(:pct, pct)
      |> assign(:compare_pct, compare_pct)
      |> assign(:state_pct, state_pct)
      |> assign(:score_display, if(assigns.score, do: Decimal.round(assigns.score, 2), else: nil))
      |> assign(
        :compare_display,
        if(assigns.compare, do: Decimal.round(assigns.compare, 2), else: nil)
      )
      |> assign(
        :state_display,
        if(assigns.state, do: Decimal.round(assigns.state, 2), else: nil)
      )
      |> assign(:quarter, div(assigns.max, 4))
      |> assign(:half, div(assigns.max, 2))
      |> assign(:three_quarter, div(assigns.max * 3, 4))

    ~H"""
    <div class="space-y-1">
      <%!-- Header: subject label + score badges --%>
      <div class="flex items-center justify-between text-xs mb-1">
        <span class="font-semibold text-base-content/70">{@subject}</span>
        <div class="flex items-center gap-4">
          <span :if={@state_display} class="flex items-center gap-1.5">
            <span class="inline-block w-2 h-2 rounded-full bg-success"></span>
            <span class="tabular-nums text-success font-semibold">{@state_display}</span>
          </span>
          <span :if={@compare_display} class="flex items-center gap-1.5">
            <span class="inline-block w-2 h-2 rounded-full bg-warning"></span>
            <span class="tabular-nums text-warning font-semibold">{@compare_display}</span>
          </span>
          <span class="flex items-center gap-1.5">
            <span class="inline-block w-2 h-2 rounded-full bg-info"></span>
            <span class="tabular-nums text-info font-semibold">
              {if @score_display, do: @score_display, else: "—"}
            </span>
          </span>
        </div>
      </div>
      <%!-- School bar --%>
      <div class="flex items-center gap-2">
        <span class="text-xs text-base-content/40 w-20 truncate text-right">{@label}</span>
        <div class="flex-1 bg-base-200 h-5 relative">
          <div class="h-5 bg-info/70 transition-all duration-500" style={"width: #{@pct}%"}></div>

          <div
            :if={@compare_pct}
            class="absolute top-0 bottom-0 w-0.5 bg-warning"
            style={"left: #{@compare_pct}%"}
            title={"#{@compare_label}: #{@compare_display}"}
          >
          </div>

          <div
            :if={@state_pct}
            class="absolute top-0 bottom-0 w-0.5 bg-success"
            style={"left: #{@state_pct}%"}
            title={"#{@state_label}: #{@state_display}"}
          >
          </div>

          <div
            class="absolute top-0 bottom-0 w-px bg-base-400/40 pointer-events-none"
            style="left: 25%"
          >
          </div>

          <div
            class="absolute top-0 bottom-0 w-px bg-base-400/40 pointer-events-none"
            style="left: 50%"
          >
          </div>

          <div
            class="absolute top-0 bottom-0 w-px bg-base-400/40 pointer-events-none"
            style="left: 75%"
          >
          </div>
        </div>
      </div>
      <%!-- LEA compare bar --%>
      <div :if={@compare_label} class="flex items-center gap-2">
        <span class="text-xs text-base-content/40 w-20 truncate text-right">{@compare_label}</span>
        <div class="flex-1 bg-base-200 h-5 relative">
          <div
            class="h-5 bg-warning/70 transition-all duration-500"
            style={"width: #{@compare_pct || 0}%"}
          >
          </div>

          <div
            :if={@pct > 0}
            class="absolute top-0 bottom-0 w-0.5 bg-info"
            style={"left: #{@pct}%"}
            title={"#{@label}: #{@score_display}"}
          >
          </div>

          <div
            class="absolute top-0 bottom-0 w-px bg-base-400/40 pointer-events-none"
            style="left: 25%"
          >
          </div>

          <div
            class="absolute top-0 bottom-0 w-px bg-base-400/40 pointer-events-none"
            style="left: 50%"
          >
          </div>

          <div
            class="absolute top-0 bottom-0 w-px bg-base-400/40 pointer-events-none"
            style="left: 75%"
          >
          </div>
        </div>
      </div>
      <%!-- State bar --%>
      <div :if={@state_f} class="flex items-center gap-2">
        <span class="text-xs text-base-content/40 w-20 truncate text-right">{@state_label}</span>
        <div class="flex-1 bg-base-200 h-5 relative">
          <div
            class="h-5 bg-success/70 transition-all duration-500"
            style={"width: #{@state_pct}%"}
          >
          </div>

          <div
            :if={@pct > 0}
            class="absolute top-0 bottom-0 w-0.5 bg-info"
            style={"left: #{@pct}%"}
            title={"#{@label}: #{@score_display}"}
          >
          </div>

          <div
            class="absolute top-0 bottom-0 w-px bg-base-400/40 pointer-events-none"
            style="left: 25%"
          >
          </div>

          <div
            class="absolute top-0 bottom-0 w-px bg-base-400/40 pointer-events-none"
            style="left: 50%"
          >
          </div>

          <div
            class="absolute top-0 bottom-0 w-px bg-base-400/40 pointer-events-none"
            style="left: 75%"
          >
          </div>
        </div>
      </div>
      <%!-- Scale labels --%>
      <div class="flex items-center gap-2">
        <span class="w-20 shrink-0"></span>
        <div class="flex-1 flex justify-between text-xs text-base-content/30 tabular-nums mt-0.5">
          <span>0</span> <span>{@quarter}</span> <span>{@half}</span> <span>{@three_quarter}</span>
          <span>{@max}</span>
        </div>
      </div>
      <%!-- Delta badges --%>
      <div :if={@score_f && (@compare_f || @state_f)} class="flex justify-end gap-2">
        <% delta_compare =
          if @score_f && @compare_f, do: Float.round(@score_f - @compare_f, 1), else: nil %> <% delta_state =
          if @score_f && @state_f, do: Float.round(@score_f - @state_f, 1), else: nil %>
        <span
          :if={delta_compare}
          class={[
            "text-xs font-semibold tabular-nums px-1.5 py-0.5",
            if(delta_compare >= 0, do: "text-success bg-success/10", else: "text-error bg-error/10")
          ]}
        >
          {if delta_compare >= 0, do: "+#{delta_compare}", else: "#{delta_compare}"} pts vs {@compare_label ||
            "LEA"}
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

  attr :subject, :string, required: true
  attr :primary, :any, default: nil
  attr :primary_label, :string, default: ""
  attr :compare, :any, default: nil
  attr :compare_label, :string, default: nil

  # Mean SGP bar (0-100 scale, though the real range is 1-99) with a fixed,
  # labeled reference line at 50 — the "typical growth" threshold.
  def sgp_subject_bar(assigns) do
    primary_f = if assigns.primary, do: Decimal.to_float(assigns.primary), else: nil
    compare_f = if assigns.compare, do: Decimal.to_float(assigns.compare), else: nil

    assigns =
      assigns
      |> assign(:primary_f, primary_f)
      |> assign(:compare_f, compare_f)
      |> assign(:primary_display, format_index(assigns.primary))
      |> assign(:compare_display, format_index(assigns.compare))

    ~H"""
    <div class="space-y-1.5">
      <div class="flex items-center justify-between text-xs mb-1">
        <span class="font-semibold text-base-content/70">{@subject}</span>
        <div class="flex items-center gap-4">
          <span :if={@compare_f} class="flex items-center gap-1.5">
            <span class="inline-block w-2 h-2 rounded-full bg-warning"></span>
            <span class="tabular-nums text-warning font-semibold">{@compare_display}</span>
          </span>
          <span class="flex items-center gap-1.5">
            <span class="inline-block w-2 h-2 rounded-full bg-info"></span>
            <span class="tabular-nums text-info font-semibold">{@primary_display}</span>
          </span>
        </div>
      </div>
      <%!-- Primary bar --%>
      <div class="flex items-center gap-2">
        <span class="text-xs text-base-content/40 w-20 truncate text-right">{@primary_label}</span>
        <div class="flex-1 bg-base-200 h-5 relative">
          <div
            class="h-5 bg-info/70 transition-all duration-500"
            style={"width: #{if @primary_f, do: min(@primary_f, 100), else: 0}%"}
          >
          </div>

          <div
            :if={@compare_f}
            class="absolute top-0 bottom-0 w-0.5 bg-warning"
            style={"left: #{min(@compare_f, 100)}%"}
            title={"#{@compare_label}: #{@compare_display}"}
          >
          </div>
          <%!-- 50 = typical growth reference line --%>
          <div
            class="absolute top-0 bottom-0 w-0.5 border-l-2 border-dashed border-base-content/40 pointer-events-none"
            style="left: 50%"
            title="50 = typical growth"
          >
          </div>
        </div>
      </div>
      <%!-- Compare bar --%>
      <div :if={@compare_label} class="flex items-center gap-2">
        <span class="text-xs text-base-content/40 w-20 truncate text-right">{@compare_label}</span>
        <div class="flex-1 bg-base-200 h-5 relative">
          <div
            class="h-5 bg-warning/70 transition-all duration-500"
            style={"width: #{if @compare_f, do: min(@compare_f, 100), else: 0}%"}
          >
          </div>

          <div
            :if={@primary_f}
            class="absolute top-0 bottom-0 w-0.5 bg-info"
            style={"left: #{min(@primary_f, 100)}%"}
            title={"#{@primary_label}: #{@primary_display}"}
          >
          </div>

          <div
            class="absolute top-0 bottom-0 w-0.5 border-l-2 border-dashed border-base-content/40 pointer-events-none"
            style="left: 50%"
          >
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :value, :any, default: nil
  attr :color, :string, default: "info"
  attr :suppressed, :boolean, default: false
  attr :approximate, :boolean, default: false

  def pct_badge(assigns) do
    ~H"""
    <span class={[
      "font-semibold tabular-nums",
      "text-#{@color}",
      @approximate && "bg-yellow-200 px-1 rounded"
    ]}>
      {cond do
        @value && @approximate -> "#{@value}%*"
        @value -> "#{@value}%"
        @suppressed -> "*"
        true -> "—"
      end}
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
    # Use the snapshots table — small, indexed on school_year, avoids scanning
    # the large MdeStateAssessmentResult table just to get a few distinct years.
    MdeDistrictSnapshot
    |> Ash.Query.select([:school_year])
    |> Ash.Query.sort(:school_year)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.school_year)
    |> Enum.uniq()
  end

  defp load_all_districts do
    # Select only the columns needed for the compare dropdown.
    MdeDistrict
    |> Ash.Query.select([:district_code, :district_name, :entity_type])
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

  @crd_top_n 10

  # CRD comparison: the charter (district_code) vs the enrollment-weighted
  # composite of the districts its nonresident students would otherwise attend.
  #
  # Resident districts are joined to MdeDistrict by the importer-resolved
  # `mde_district_id` (NOT the unreliable crd_district_code), then scored via the
  # same MdeDistrictSnapshot rollup used elsewhere. Districts without a snapshot
  # for the year are shown but excluded from the weighted composite.
  #
  # Two scopes are computed up front so the UI toggle is instant: `all` resident
  # districts, and `top10` — the #{@crd_top_n} sending the most nonresident
  # students. The charter's own scores are scope-independent.
  defp load_crd_comparison(charter_code, year) do
    rows =
      MdeCompositeResidentDistrict
      |> Ash.Query.filter(charter_district_code == ^charter_code)
      |> Ash.Query.load(:mde_district)
      |> Ash.Query.sort(nonresident_students_enrolled: :desc)
      |> Ash.read!(authorize?: false)

    charter = load_district_data(charter_code, year)
    charter_sat = sat_scores(load_sat_lea_result(charter_code, year))
    charter_sgp = sgp_subject_averages(charter_code, year)
    charter_sgp_avg = avg_of_subjects(charter_sgp)

    residents =
      Enum.map(rows, fn r ->
        code = r.mde_district && r.mde_district.district_code
        data = if code, do: load_district_data(code, year)
        sat = if code, do: sat_scores(load_sat_lea_result(code, year))
        sgp = if code, do: sgp_subject_averages(code, year), else: %{}
        subjects = (data && data.all_subjects) || %{}

        %{
          resident_name: r.resident_entity_name,
          district_code: code,
          weight: r.nonresident_students_enrolled || 0,
          subjects: subjects,
          avg: avg_of_subjects(subjects),
          has_data: not is_nil(data),
          sat: sat,
          has_sat: not is_nil(sat),
          sgp: sgp,
          sgp_avg: avg_of_subjects(sgp),
          has_sgp: map_size(sgp) > 0
        }
      end)

    # Subject is free text in the SGP source data (e.g. "English Language Arts",
    # not the "ELA" abbreviation the rest of this module hardcodes in @subjects)
    # — derive it from whatever's actually present rather than assuming a match.
    sgp_subjects =
      (Map.keys(charter_sgp) ++ Enum.flat_map(residents, &Map.keys(&1.sgp)))
      |> Enum.uniq()
      |> Enum.sort()

    all_summary = crd_scope_summary(residents, sgp_subjects)
    top10_summary = crd_scope_summary(Enum.take(residents, @crd_top_n), sgp_subjects)

    %{
      charter_name: charter && charter.district_name,
      charter_subjects: (charter && charter.all_subjects) || %{},
      charter_avg: charter && avg_of_subjects(charter.all_subjects),
      charter_sat: charter_sat,
      has_any_sat: not is_nil(charter_sat) or all_summary.sat_scored_count > 0,
      charter_sgp: charter_sgp,
      charter_sgp_avg: charter_sgp_avg,
      has_any_sgp: charter_sgp_avg != nil or all_summary.sgp_scored_count > 0,
      sgp_subjects: sgp_subjects,
      total_residents: length(rows),
      # `residents` is already sorted by enrollment desc, so the top-N is a prefix.
      all: all_summary,
      top10: top10_summary
    }
  end

  # Build one scope's view: the enrollment-weighted M-STEP, SAT, and SGP
  # composites over the scored subsets, plus the resident rows to display.
  defp crd_scope_summary(residents, sgp_subjects) do
    scored = Enum.filter(residents, & &1.has_data)
    sat_scored = Enum.filter(residents, & &1.has_sat)
    sgp_scored = Enum.filter(residents, & &1.has_sgp)
    composite_subjects = Map.new(@subjects, fn s -> {s, weighted_subject(scored, s)} end)

    composite_sgp_subjects =
      Map.new(sgp_subjects, fn s -> {s, weighted_sgp_subject(sgp_scored, s)} end)

    %{
      residents: residents,
      composite_subjects: composite_subjects,
      composite_avg: avg_of_subjects(composite_subjects),
      district_count: length(residents),
      scored_count: length(scored),
      total_students: Enum.sum(Enum.map(scored, & &1.weight)),
      sat_composite: %{
        math: weighted_sat(sat_scored, :math),
        ebrw: weighted_sat(sat_scored, :ebrw),
        all: weighted_sat(sat_scored, :all)
      },
      sat_scored_count: length(sat_scored),
      sat_total_students: Enum.sum(Enum.map(sat_scored, & &1.weight)),
      composite_sgp_subjects: composite_sgp_subjects,
      composite_sgp_avg: avg_of_subjects(composite_sgp_subjects),
      sgp_scored_count: length(sgp_scored),
      sgp_total_students: Enum.sum(Enum.map(sgp_scored, & &1.weight))
    }
  end

  # Extract the three district-level SAT averages from a MdeSatResult row.
  defp sat_scores(nil), do: nil

  defp sat_scores(row) do
    %{
      math: row.math_score_average,
      ebrw: row.ebrw_score_average,
      all: row.all_subject_score_average
    }
  end

  # Enrollment-weighted mean of one SAT metric across districts that have it.
  defp weighted_sat(scored, key) do
    {weighted_sum, weight} =
      Enum.reduce(scored, {0.0, 0}, fn rd, {sum, w} ->
        case rd.sat && Map.get(rd.sat, key) do
          nil -> {sum, w}
          d -> {sum + Decimal.to_float(d) * rd.weight, w + rd.weight}
        end
      end)

    if weight > 0, do: Decimal.from_float(Float.round(weighted_sum / weight, 1)), else: nil
  end

  # Enrollment-weighted mean of one subject's proficiency across scored districts.
  defp weighted_subject(scored, subject) do
    {weighted_sum, weight} =
      Enum.reduce(scored, {0.0, 0}, fn rd, {sum, w} ->
        case Map.get(rd.subjects, subject) do
          nil -> {sum, w}
          d -> {sum + Decimal.to_float(d) * rd.weight, w + rd.weight}
        end
      end)

    if weight > 0, do: Decimal.from_float(Float.round(weighted_sum / weight, 1)), else: nil
  end

  # A district's mean SGP per subject, averaged across grades (weighted by
  # each grade's total_included), for the "All Students" subgroup. Shape
  # matches `all_subjects` (%{subject => decimal}) so it works with
  # `avg_of_subjects/1` — but subject keys are whatever's in the SGP source
  # data (free text), not the app's hardcoded @subjects list.
  defp sgp_subject_averages(nil, _year), do: %{}

  defp sgp_subject_averages(district_code, year) do
    MdeSgpResult
    |> Ash.Query.filter(
      rollup_level == :district and
        mde_district.district_code == ^district_code and
        school_year == ^year and
        testing_group == "All Students"
    )
    |> Ash.read!(authorize?: false)
    |> Enum.group_by(& &1.subject)
    |> Map.new(fn {subject, rows} -> {subject, weighted_mean_sgp(rows)} end)
  rescue
    _ -> %{}
  end

  # Enrollment-weighted (by total_included) mean SGP across a subject's grade rows.
  defp weighted_mean_sgp(rows) do
    {weighted_sum, weight} =
      rows
      |> Enum.filter(&(&1.mean_sgp && &1.total_included))
      |> Enum.reduce({0.0, 0}, fn r, {sum, w} ->
        {sum + Decimal.to_float(r.mean_sgp) * r.total_included, w + r.total_included}
      end)

    if weight > 0, do: Decimal.from_float(Float.round(weighted_sum / weight, 1)), else: nil
  end

  # Enrollment-weighted mean of one subject's Mean SGP across scored districts.
  defp weighted_sgp_subject(scored, subject) do
    {weighted_sum, weight} =
      Enum.reduce(scored, {0.0, 0}, fn rd, {sum, w} ->
        case Map.get(rd.sgp, subject) do
          nil -> {sum, w}
          d -> {sum + Decimal.to_float(d) * rd.weight, w + rd.weight}
        end
      end)

    if weight > 0, do: Decimal.from_float(Float.round(weighted_sum / weight, 1)), else: nil
  end

  # Simple mean of the (non-nil) subject proficiencies in a subject map.
  defp avg_of_subjects(map) when is_map(map) do
    vals =
      map
      |> Map.values()
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Decimal.to_float/1)

    case vals do
      [] -> nil
      list -> Decimal.from_float(Float.round(Enum.sum(list) / length(list), 1))
    end
  end

  defp avg_of_subjects(_), do: nil

  defp load_district_buildings(district_code) do
    MdeBuilding
    |> Ash.Query.filter(mde_district.district_code == ^district_code)
    |> Ash.Query.sort(:building_name)
    |> Ash.read!(authorize?: false)
    |> Enum.group_by(fn b ->
      case String.trim_leading(b.building_code || "", "0") do
        "" -> "0"
        c -> c
      end
    end)
    |> Map.values()
    |> Enum.map(fn group -> Enum.min_by(group, &String.length(&1.building_code || "")) end)
    |> Enum.sort_by(& &1.building_name)
  end

  defp load_enrollment(building_code, year) do
    MdeEnrollmentResult
    |> Ash.Query.filter(
      building_code == ^building_code and school_year == ^year and rollup_level == :building
    )
    |> Ash.read_one!(authorize?: false)
  end

  defp load_lea_enrollment(lea_district_code, year) do
    MdeEnrollmentResult
    |> Ash.Query.filter(
      district_code == ^lea_district_code and school_year == ^year and rollup_level == :district
    )
    |> Ash.read_one!(authorize?: false)
  end

  defp load_sat_results(building_code, year) do
    MdeSatResult
    |> Ash.Query.filter(
      building_code == ^building_code and school_year == ^year and rollup_level == :building
    )
    |> Ash.Query.sort(:subgroup)
    |> Ash.read!(authorize?: false)
  end

  defp load_sat_lea_result(lea_district_code, year) do
    MdeSatResult
    |> Ash.Query.filter(
      district_code == ^lea_district_code and school_year == ^year and
        rollup_level == :district and subgroup == "All Students"
    )
    |> Ash.read_one!(authorize?: false)
  end

  # State aggregate row: ISDCode=0, DistrictCode=0, BuildingCode=0 → stored as rollup_level :isd with isd_code "0"
  defp load_sat_state_result(year) do
    MdeSatResult
    |> Ash.Query.filter(
      rollup_level == :isd and isd_code == "0" and school_year == ^year and
        subgroup == "All Students"
    )
    |> Ash.read_one!(authorize?: false)
  end

  defp load_econ_grade_breakdown(building_code, lea_district_code, year) do
    # Three independent queries — run in parallel.
    school_task =
      Task.async(fn ->
        MdeStateAssessmentResult
        |> Ash.Query.filter(
          rollup_level == :building and
            mde_building.building_code == ^building_code and
            school_year == ^year and
            report_category == "Economically Disadvantaged" and
            grade_content_tested != "All"
        )
        |> Ash.read!(authorize?: false)
      end)

    lea_task =
      Task.async(fn ->
        if lea_district_code do
          MdeStateAssessmentResult
          |> Ash.Query.filter(
            rollup_level == :district and
              mde_district.district_code == ^lea_district_code and
              school_year == ^year and
              report_category == "Economically Disadvantaged" and
              grade_content_tested != "All"
          )
          |> Ash.read!(authorize?: false)
        else
          []
        end
      end)

    state_task =
      Task.async(fn ->
        MdeStateAssessmentResult
        |> Ash.Query.filter(
          rollup_level == :isd and
            mde_isd.isd_code == "0" and
            school_year == ^year and
            report_category == "Economically Disadvantaged" and
            grade_content_tested != "All"
        )
        |> Ash.read!(authorize?: false)
      end)

    school_rows = Task.await(school_task)
    lea_rows = Task.await(lea_task)
    state_rows = Task.await(state_task)

    school_grades = Enum.group_by(school_rows, & &1.grade_content_tested)
    lea_grades = Enum.group_by(lea_rows, & &1.grade_content_tested)
    state_grades = Enum.group_by(state_rows, & &1.grade_content_tested)

    all_grades =
      (Map.keys(school_grades) ++ Map.keys(lea_grades))
      |> Enum.uniq()
      |> Enum.sort()

    Enum.map(all_grades, fn grade ->
      s = Map.get(school_grades, grade, [])
      l = Map.get(lea_grades, grade, [])
      st = Map.get(state_grades, grade, [])

      school_ela_rows = Enum.filter(s, &(&1.subject == "ELA"))
      school_math_rows = Enum.filter(s, &(&1.subject == "Mathematics"))

      %{
        grade: grade,
        school_ela: school_ela_rows |> weighted_proficiency_float() |> maybe_decimal(),
        school_ela_suppressed: all_suppressed?(school_ela_rows),
        school_ela_approximate: any_approximate?(school_ela_rows),
        lea_ela:
          l
          |> Enum.filter(&(&1.subject == "ELA"))
          |> weighted_proficiency_float()
          |> maybe_decimal(),
        state_ela:
          st
          |> Enum.filter(&(&1.subject == "ELA"))
          |> weighted_proficiency_float()
          |> maybe_decimal(),
        school_math: school_math_rows |> weighted_proficiency_float() |> maybe_decimal(),
        school_math_suppressed: all_suppressed?(school_math_rows),
        school_math_approximate: any_approximate?(school_math_rows),
        lea_math:
          l
          |> Enum.filter(&(&1.subject == "Mathematics"))
          |> weighted_proficiency_float()
          |> maybe_decimal(),
        state_math:
          st
          |> Enum.filter(&(&1.subject == "Mathematics"))
          |> weighted_proficiency_float()
          |> maybe_decimal()
      }
    end)
  end

  defp all_suppressed?([]), do: false

  defp all_suppressed?(rows) do
    Enum.all?(rows, fn r ->
      r.percent_met_suppressed or (is_nil(r.percent_met) and (r.number_assessed || 0) == 0)
    end)
  end

  defp any_approximate?([]), do: false
  defp any_approximate?(rows), do: Enum.any?(rows, & &1.percent_met_approximate)

  defp weighted_proficiency_float([]), do: nil

  defp weighted_proficiency_float(rows) do
    {total_assessed, total_prof} =
      rows
      |> Enum.reject(& &1.percent_met_suppressed)
      |> Enum.reduce({0, 0.0}, fn r, {assessed, prof} ->
        pct = if r.percent_met, do: Decimal.to_float(r.percent_met), else: 0.0
        n = r.number_assessed || 0
        {assessed + n, prof + pct * n / 100.0}
      end)

    if total_assessed > 0, do: Float.round(total_prof / total_assessed * 100.0, 1), else: nil
  end

  defp maybe_decimal(nil), do: nil
  defp maybe_decimal(f), do: Decimal.from_float(f)

  defp format_index(nil), do: "—"
  defp format_index(d), do: d |> Decimal.round(2, :floor) |> Decimal.to_string()

  defp overall_score_class(nil, _threshold), do: "text-primary"
  defp overall_score_class(_value, nil), do: "text-primary"

  defp overall_score_class(value, threshold) do
    if Decimal.compare(value, threshold) == :lt, do: "text-error", else: "text-success"
  end

  defp load_index_thresholds(year) do
    si_year = school_index_year(year)

    Emisint.Assessments.MdeIndexThreshold
    |> Ash.Query.filter(school_year == ^si_year)
    |> Ash.read!(authorize?: false)
    |> Map.new(fn t -> {t.component, t.threshold_value} end)
  rescue
    _ -> %{}
  end

  defp load_school_index(building_code, year) do
    si_year = school_index_year(year)

    MdeSchoolIndexResult
    |> Ash.Query.filter(mde_building.building_code == ^building_code and school_year == ^si_year)
    |> Ash.read_one!(authorize?: false)
  rescue
    _ -> nil
  end

  # SGP school_year is stored in the same "24 - 25 School Year" format as the
  # rest of the app (M-STEP/SAT), unlike School Index which uses "2024-2025" —
  # so no conversion is needed here, just a direct filter.
  defp load_sgp_results(building_code, year) do
    rows =
      MdeSgpResult
      |> Ash.Query.filter(
        mde_building.building_code == ^building_code and
          school_year == ^year and
          testing_group == "All Students"
      )
      |> Ash.read!(authorize?: false)

    subjects = rows |> Enum.map(& &1.subject) |> Enum.uniq() |> Enum.sort()

    grades =
      rows
      |> Enum.group_by(& &1.grade)
      |> Enum.map(fn {grade, grade_rows} ->
        %{grade: grade, by_subject: Map.new(grade_rows, &{&1.subject, &1})}
      end)
      |> Enum.sort_by(& &1.grade)

    %{subjects: subjects, grades: grades}
  rescue
    _ -> %{subjects: [], grades: []}
  end

  # Generic "primary vs. compare" SGP merge — used for both School vs. LEA
  # (primary = school, compare = LEA district) and District vs. District.
  defp sgp_comparison_rows(primary_sgp, compare_sgp) do
    subjects = (primary_sgp.subjects ++ compare_sgp.subjects) |> Enum.uniq() |> Enum.sort()

    primary_by_grade = Map.new(primary_sgp.grades, &{&1.grade, &1.by_subject})
    compare_by_grade = Map.new(compare_sgp.grades, &{&1.grade, &1.by_subject})

    grades =
      (Map.keys(primary_by_grade) ++ Map.keys(compare_by_grade))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn grade ->
        primary_subjects = Map.get(primary_by_grade, grade, %{})
        compare_subjects = Map.get(compare_by_grade, grade, %{})

        by_subject =
          Map.new(subjects, fn subject ->
            {subject,
             %{
               primary: Map.get(primary_subjects, subject),
               compare: Map.get(compare_subjects, subject)
             }}
          end)

        %{grade: grade, by_subject: by_subject}
      end)

    %{subjects: subjects, grades: grades}
  end

  defp load_sgp_lea_result(lea_district_code, year) do
    rows =
      MdeSgpResult
      |> Ash.Query.filter(
        rollup_level == :district and
          mde_district.district_code == ^lea_district_code and
          school_year == ^year and
          testing_group == "All Students"
      )
      |> Ash.read!(authorize?: false)

    subjects = rows |> Enum.map(& &1.subject) |> Enum.uniq() |> Enum.sort()

    grades =
      rows
      |> Enum.group_by(& &1.grade)
      |> Enum.map(fn {grade, grade_rows} ->
        %{grade: grade, by_subject: Map.new(grade_rows, &{&1.subject, &1})}
      end)
      |> Enum.sort_by(& &1.grade)

    %{subjects: subjects, grades: grades}
  rescue
    _ -> %{subjects: [], grades: []}
  end

  # Collapses a %{subjects:, grades:} SGP structure (from load_sgp_results/2 or
  # load_sgp_lea_result/2) down to one "all grades" Mean SGP per subject,
  # weighted by each grade row's total_included — reuses the same weighting
  # as weighted_mean_sgp/1 (built for the CRD tab's district-level averages).
  defp sgp_all_grades_by_subject(%{subjects: subjects, grades: grades}) do
    Map.new(subjects, fn subject ->
      rows =
        grades
        |> Enum.map(&Map.get(&1.by_subject, subject))
        |> Enum.reject(&is_nil/1)

      {subject, weighted_mean_sgp(rows)}
    end)
  end

  defp sgp_subject_selected?(_subject, nil), do: true
  defp sgp_subject_selected?(subject, %MapSet{} = filter), do: MapSet.member?(filter, subject)

  defp sgp_score_class(nil), do: "text-base-content/40"

  defp sgp_score_class(value) do
    if Decimal.compare(value, 50) == :lt, do: "text-error", else: "text-success"
  end

  # Converts "24 - 25 School Year" → "2024-2025"
  defp school_index_year(year) do
    year
    |> String.replace(" School Year", "")
    |> String.split(" - ")
    |> case do
      [y1, y2] -> "20#{String.trim(y1)}-20#{String.trim(y2)}"
      _ -> year
    end
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
        school_ela_suppressed: row["school_ela_suppressed"] || false,
        school_ela_approximate: row["school_ela_approximate"] || false,
        lea_ela: float_to_decimal(row["lea_ela"]),
        state_ela: float_to_decimal(row["state_ela"]),
        school_math: float_to_decimal(row["school_math"]),
        school_math_suppressed: row["school_math_suppressed"] || false,
        school_math_approximate: row["school_math_approximate"] || false,
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

  # Pick the active CRD scope sub-map (all vs top10) for the current toggle.
  defp crd_view(%{crd_comparison: nil}), do: nil
  defp crd_view(%{crd_comparison: c, crd_scope: "top10"}), do: c.top10
  defp crd_view(%{crd_comparison: c}), do: c.all

  defp crd_scope_btn_class(true),
    do: "px-3 py-1.5 text-xs font-semibold bg-info text-white"

  defp crd_scope_btn_class(false),
    do:
      "px-3 py-1.5 text-xs font-medium bg-base-100 text-base-content/60 hover:bg-base-200 transition-colors"

  defp subject_abbr("Mathematics"), do: "Math"
  defp subject_abbr("Science"), do: "Sci"
  defp subject_abbr("Social Studies"), do: "SS"
  defp subject_abbr(subject), do: subject

  # SAT scores are scaled averages (not percentages); render to 1 decimal.
  defp fmt_sat(nil), do: "—"
  defp fmt_sat(d), do: d |> Decimal.round(1) |> Decimal.to_string()

  defp crd_scope_label("top10"), do: "Top 10 CRD"
  defp crd_scope_label(_), do: "CRD Composite"

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

  defp build_breadcrumbs(%{from: "esp", from_emo: emo} = assigns) when not is_nil(emo) do
    district_label =
      if assigns.primary, do: assigns.primary.district_name, else: "District Analysis"

    [
      %{label: "ESP Portfolio", to: ~p"/esp-portfolio"},
      %{label: emo, to: ~p"/esp-portfolio?#{%{emo: emo}}"},
      %{label: district_label}
    ]
  end

  defp build_breadcrumbs(%{from: "portfolio", from_agency: agency_code} = assigns)
       when not is_nil(agency_code) do
    agency_label = assigns.from_agency_name || agency_code

    district_label =
      if assigns.primary, do: assigns.primary.district_name, else: "District Analysis"

    [
      %{label: "Authorizer Portfolio", to: ~p"/authorizer-portfolio"},
      %{label: agency_label, to: ~p"/authorizer-portfolio?#{%{agency: agency_code}}"},
      %{label: district_label}
    ]
  end

  defp build_breadcrumbs(assigns) do
    district_label =
      if assigns.primary, do: assigns.primary.district_name, else: "District Analysis"

    [%{label: "MDE Overview", to: ~p"/mde"}, %{label: district_label}]
  end

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
