defmodule EmisintWeb.Mde.OverviewLive do
  use EmisintWeb, :live_view

  require Ash.Query

  alias Emisint.Assessments.MdeDistrictSnapshot
  alias Emisint.Assessments.MdeEntityMaster
  alias Emisint.Assessments.MdeSatResult

  @page_size 100

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  def mount(_params, _session, socket) do
    years = load_school_years()
    selected_year = List.last(years)

    socket =
      socket
      |> assign(:page_title, "MDE State Assessments")
      |> assign(:school_years, years)
      |> assign(:selected_year, selected_year)
      |> assign(:entity_districts, [])
      |> assign(:all_districts, [])
      |> assign(:snapshot_map, %{})
      |> assign(:district_count, 0)
      |> assign(:page_offset, 0)
      |> assign(:district_search, "")
      |> stream(:district_rows, [])
      |> assign(:selected_district, nil)

    # Defer the DB query to the connected mount — the disconnected pass (HTTP)
    # only renders static HTML so loading data there is wasteful.
    if connected?(socket) && selected_year do
      entity_districts = load_entity_master_districts()
      snapshot_map = load_snapshot_map(selected_year)
      all_districts = merge_districts(entity_districts, snapshot_map)

      socket =
        socket
        |> assign(:entity_districts, entity_districts)
        |> assign(:snapshot_map, snapshot_map)
        |> assign(:all_districts, all_districts)

      {:ok, apply_filter_and_page(socket, "", 0)}
    else
      {:ok, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  def handle_event("select_year", %{"year" => year}, socket) do
    snapshot_map = load_snapshot_map(year)
    all_districts = merge_districts(socket.assigns.entity_districts, snapshot_map)

    socket =
      socket
      |> assign(:selected_year, year)
      |> assign(:snapshot_map, snapshot_map)
      |> assign(:all_districts, all_districts)
      |> assign(:selected_district, nil)

    {:noreply, apply_filter_and_page(socket, "", 0)}
  end

  def handle_event("search_districts", %{"search" => search}, socket) do
    {:noreply, apply_filter_and_page(socket, search, 0)}
  end

  def handle_event("prev_page", _params, socket) do
    new_offset = max(0, socket.assigns.page_offset - @page_size)
    {:noreply, apply_filter_and_page(socket, socket.assigns.district_search, new_offset)}
  end

  def handle_event("next_page", _params, socket) do
    new_offset = socket.assigns.page_offset + @page_size
    {:noreply, apply_filter_and_page(socket, socket.assigns.district_search, new_offset)}
  end

  def handle_event("show_district", %{"code" => code}, socket) do
    snapshot = Map.get(socket.assigns.snapshot_map, code)

    selected =
      if snapshot do
        snapshot_to_district_row(snapshot)
      else
        em = Enum.find(socket.assigns.all_districts, &(&1.district_code == code))
        em && entity_district_to_row(em)
      end

    {:noreply, assign(socket, :selected_district, selected)}
  end

  def handle_event("close_district", _params, socket) do
    {:noreply, assign(socket, :selected_district, nil)}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  def render(assigns) do
    assigns = assign(assigns, :page_size, @page_size)

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
            <form>
              <select
                name="year"
                phx-change="select_year"
                class="border border-base-300 bg-base-100 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-info/25 focus:border-info transition-all"
              >
                <option :for={year <- @school_years} value={year} selected={year == @selected_year}>
                  {year}
                </option>
              </select>
            </form>
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

        <%!-- ── District Breakdown Table ──────────────────────────────────────── --%>
        <div :if={@district_count > 0 || @district_search != ""} class="space-y-3">
          <div class="flex items-center gap-2">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
              District Breakdown
            </h2>
            <div class="flex-1 h-px bg-base-200"></div>
            <span class="text-xs text-base-content/35">click a row for details</span>
          </div>

          <%!-- Search --%>
          <form phx-change="search_districts" class="flex items-center gap-3">
            <div class="relative flex-1 max-w-xs">
              <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                <.icon name="hero-magnifying-glass" class="size-4 text-base-content/35" />
              </div>
              <input
                type="text"
                name="search"
                value={@district_search}
                placeholder="Search districts…"
                class="w-full pl-9 pr-3 py-2 border border-base-300 bg-base-50 text-sm focus:outline-none focus:ring-2 focus:ring-info/25 focus:border-info transition-all"
                phx-debounce="300"
              />
            </div>
            <span class="text-xs text-base-content/40">
              {@district_count} {if @district_search != "", do: "matching", else: "total"} districts
            </span>
          </form>

          <%!-- No search results --%>
          <div
            :if={@district_count == 0}
            class="bg-base-100 border border-base-200 flex flex-col items-center justify-center py-10 text-center"
          >
            <div class="p-3 bg-base-200 mb-3">
              <.icon name="hero-funnel" class="size-5 text-base-content/25" />
            </div>
            <p class="text-sm font-medium text-base-content/40">No districts match your search</p>
          </div>

          <div :if={@district_count > 0} class="bg-base-100 border border-base-200 overflow-hidden">
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
                    <th class="text-center px-4 py-3 font-medium text-base-content/60 text-xs uppercase tracking-wide">
                      Buildings
                    </th>
                    <th class="text-center px-4 py-3 font-medium text-base-content/60 text-xs uppercase tracking-wide hidden md:table-cell">
                      M-STEP Data
                    </th>
                  </tr>
                </thead>
                <tbody id="district-rows" phx-update="stream" class="divide-y divide-base-200">
                  <tr
                    :for={{dom_id, row} <- @streams.district_rows}
                    id={dom_id}
                    class="hover:bg-base-50 transition-colors cursor-pointer"
                    phx-click="show_district"
                    phx-value-code={row.id}
                  >
                    <td class="px-4 py-3 font-medium">{row.district_name}</td>
                    <td class="px-4 py-3 text-xs text-base-content/50 hidden sm:table-cell">
                      {row.entity_type || "—"}
                    </td>
                    <td class="px-4 py-3 text-center text-base-content/50">
                      {row.buildings || "—"}
                    </td>
                    <td class="px-4 py-3 text-center hidden md:table-cell">
                      <span :if={row.has_mstep} class="badge badge-success badge-xs">Yes</span>
                      <span :if={!row.has_mstep} class="badge badge-ghost badge-xs">SAT only</span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <%!-- Pagination --%>
            <div class="flex items-center justify-between px-4 py-3 border-t border-base-200 bg-base-50">
              <span class="text-xs text-base-content/50">
                {min(@page_offset + 1, @district_count)}–{min(@page_offset + @page_size, @district_count)} of {@district_count}
              </span>
              <div class="flex gap-1">
                <button
                  phx-click="prev_page"
                  disabled={@page_offset == 0}
                  class="px-3 py-1.5 text-xs border border-base-300 bg-base-100 hover:bg-base-200 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
                >
                  ← Previous
                </button>
                <button
                  phx-click="next_page"
                  disabled={@page_offset + @page_size >= @district_count}
                  class="px-3 py-1.5 text-xs border border-base-300 bg-base-100 hover:bg-base-200 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
                >
                  Next →
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- District Detail Modal --%>
      <.district_modal
        :if={@selected_district}
        district={@selected_district}
      />
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

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

  attr :district, :map, required: true
  attr :statewide, :map, default: nil

  def district_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_district"
      phx-key="Escape"
    >
      <%!-- Backdrop --%>
      <div
        class="absolute inset-0 bg-black/60 backdrop-blur-sm"
        phx-click="close_district"
      >
      </div>

      <%!-- Modal panel --%>
      <div class="relative bg-base-100 w-full max-w-3xl max-h-[88vh] overflow-y-auto shadow-2xl border border-base-200">
        <%!-- Sticky header --%>
        <div class="sticky top-0 bg-base-100 border-b border-base-200 px-6 py-4 flex items-start justify-between gap-4 z-10">
          <div>
            <h2 class="text-lg font-bold leading-tight">{@district.district_name}</h2>
            <div class="flex flex-wrap items-center gap-x-2 gap-y-0.5 mt-1 text-xs text-base-content/50">
              <span :if={@district.isd_name} class="flex items-center gap-1">
                <.icon name="hero-map-pin" class="size-3.5" />
                {@district.isd_name} ISD
              </span>
              <span :if={@district.isd_name}>·</span>
              <span :if={@district.entity_type}>{@district.entity_type}</span>
              <span :if={@district.entity_type}>·</span>
              <span>
                {@district.buildings} {if @district.buildings == 1,
                  do: "building",
                  else: "buildings"}
              </span>
              <span :if={@district.has_mstep && @district.total_assessed > 0}>·</span>
              <span :if={@district.has_mstep && @district.total_assessed > 0}>
                {format_number(@district.total_assessed)} students assessed
              </span>
            </div>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <.link
              navigate={~p"/mde/districts/#{@district.district_code}"}
              class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold bg-info text-info-content hover:bg-info/80 transition-colors"
            >
              <.icon name="hero-chart-bar" class="size-3.5" /> Analysis
            </.link>
            <button
              phx-click="close_district"
              class="p-1.5 text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>
        </div>

        <div class="p-6 space-y-8">
          <%!-- No M-STEP data notice --%>
          <div :if={!@district.has_mstep} class="flex flex-col items-center py-8 text-center">
            <div class="p-3 bg-base-200 mb-4">
              <.icon name="hero-chart-bar" class="size-7 text-base-content/25" />
            </div>
            <p class="text-sm font-medium text-base-content/50">
              No M-STEP/PSAT data for this district in the selected year.
            </p>
            <p class="text-xs text-base-content/35 mt-1">
              SAT or other assessment data may be available — click Analysis to view all data.
            </p>
          </div>

          <%!-- Section: Subject Proficiency vs Statewide --%>
          <div :if={@district.has_mstep} class="space-y-3">
            <div class="flex items-center gap-2">
              <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
                M-STEP Proficiency by Subject
              </h3>
              <div class="flex-1 h-px bg-base-200"></div>
              <span :if={@statewide} class="text-xs text-base-content/35 flex items-center gap-1.5">
                <span class="inline-block w-0.5 h-3 bg-base-content/35"></span> Statewide avg
              </span>
            </div>

            <div class="space-y-3">
              <.subject_vs_state
                :for={subj <- ["ELA", "Mathematics", "Science", "Social Studies"]}
                subject={subj}
                value={Map.get(@district.all_subjects, subj)}
                state_value={@statewide && Map.get(@statewide, subj)}
              />
            </div>
          </div>

          <%!-- Section: Grade-Level Breakdown --%>
          <div :if={@district.has_mstep && @district.grade_breakdown != []} class="space-y-3">
            <div class="flex items-center gap-2">
              <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
                Grade-Level Breakdown (ELA &amp; Math)
              </h3>
              <div class="flex-1 h-px bg-base-200"></div>
            </div>

            <div class="bg-base-50 border border-base-200 overflow-hidden">
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b border-base-200">
                    <th class="text-left px-4 py-2.5 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                      Grade
                    </th>
                    <th class="text-right px-4 py-2.5 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                      ELA %
                    </th>
                    <th class="text-right px-4 py-2.5 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                      Math %
                    </th>
                    <th class="text-right px-4 py-2.5 text-xs font-medium text-base-content/50 uppercase tracking-wide hidden sm:table-cell">
                      Students (ELA)
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-base-200">
                  <tr :for={grade_row <- @district.grade_breakdown} class="hover:bg-base-100">
                    <td class="px-4 py-2.5 font-medium text-xs">
                      {grade_label(grade_row.grade)}
                    </td>
                    <td class="px-4 py-2.5 text-right">
                      <.pct_badge value={grade_row.ela} />
                    </td>
                    <td class="px-4 py-2.5 text-right">
                      <.pct_badge value={grade_row.math} />
                    </td>
                    <td class="px-4 py-2.5 text-right text-xs text-base-content/50 hidden sm:table-cell">
                      {format_number(grade_row.students)}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <%!-- Section: Proficiency Level Distribution --%>
          <div :if={@district.has_mstep && @district.proficiency_dist} class="space-y-3">
            <div class="flex items-center gap-2">
              <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
                Proficiency Level Distribution (All M-STEP Subjects)
              </h3>
              <div class="flex-1 h-px bg-base-200"></div>
            </div>

            <%!-- Stacked bar --%>
            <div class="flex h-8 w-full overflow-hidden">
              <div
                class="bg-success flex items-center justify-center text-xs text-white font-semibold"
                style={"width: #{@district.proficiency_dist.advanced}%"}
                title={"Advanced: #{@district.proficiency_dist.advanced}%"}
              >
                {if @district.proficiency_dist.advanced >= 5,
                  do: "#{@district.proficiency_dist.advanced}%",
                  else: ""}
              </div>
              <div
                class="bg-info flex items-center justify-center text-xs text-white font-semibold"
                style={"width: #{@district.proficiency_dist.proficient}%"}
                title={"Proficient: #{@district.proficiency_dist.proficient}%"}
              >
                {if @district.proficiency_dist.proficient >= 5,
                  do: "#{@district.proficiency_dist.proficient}%",
                  else: ""}
              </div>
              <div
                class="bg-warning flex items-center justify-center text-xs text-white font-semibold"
                style={"width: #{@district.proficiency_dist.partially}%"}
                title={"Partially Proficient: #{@district.proficiency_dist.partially}%"}
              >
                {if @district.proficiency_dist.partially >= 5,
                  do: "#{@district.proficiency_dist.partially}%",
                  else: ""}
              </div>
              <div
                class="bg-error flex-1 flex items-center justify-center text-xs text-white font-semibold"
                title={"Not Proficient: #{@district.proficiency_dist.not_proficient}%"}
              >
                {if @district.proficiency_dist.not_proficient >= 5,
                  do: "#{@district.proficiency_dist.not_proficient}%",
                  else: ""}
              </div>
            </div>

            <%!-- Legend --%>
            <div class="flex flex-wrap gap-x-5 gap-y-1.5">
              <span class="flex items-center gap-1.5 text-xs text-base-content/60">
                <span class="inline-block w-2.5 h-2.5 rounded-sm bg-success"></span>
                Advanced — {@district.proficiency_dist.advanced}%
              </span>
              <span class="flex items-center gap-1.5 text-xs text-base-content/60">
                <span class="inline-block w-2.5 h-2.5 rounded-sm bg-info"></span>
                Proficient — {@district.proficiency_dist.proficient}%
              </span>
              <span class="flex items-center gap-1.5 text-xs text-base-content/60">
                <span class="inline-block w-2.5 h-2.5 rounded-sm bg-warning"></span>
                Partially Proficient — {@district.proficiency_dist.partially}%
              </span>
              <span class="flex items-center gap-1.5 text-xs text-base-content/60">
                <span class="inline-block w-2.5 h-2.5 rounded-sm bg-error"></span>
                Not Proficient — {@district.proficiency_dist.not_proficient}%
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :subject, :string, required: true
  attr :value, :any, default: nil
  attr :state_value, :any, default: nil

  def subject_vs_state(assigns) do
    val_f = if assigns.value, do: Decimal.to_float(assigns.value), else: nil
    state_f = if assigns.state_value, do: Decimal.to_float(assigns.state_value), else: nil

    color =
      cond do
        is_nil(val_f) -> "base-content/20"
        val_f >= 50.0 -> "success"
        val_f >= 35.0 -> "warning"
        true -> "error"
      end

    assigns =
      assigns
      |> assign(:val_f, val_f)
      |> assign(:state_f, state_f)
      |> assign(:color, color)

    ~H"""
    <div class="space-y-1">
      <div class="flex items-center justify-between text-xs">
        <span class="font-medium text-base-content/70">{@subject}</span>
        <div class="flex items-center gap-3">
          <span :if={@state_f} class="text-base-content/40">
            State: {@state_value}%
          </span>
          <span class={"font-semibold tabular-nums text-#{@color}"}>
            {if @value, do: "#{@value}%", else: "—"}
          </span>
        </div>
      </div>
      <%!-- Bar with statewide marker --%>
      <div class="relative w-full bg-base-200 h-4">
        <div
          class={"h-4 transition-all duration-500 bg-#{@color}/70"}
          style={"width: #{if @val_f, do: min(@val_f, 100), else: 0}%"}
        >
        </div>
        <%!-- Statewide average tick --%>
        <div
          :if={@state_f}
          class="absolute top-0 bottom-0 w-0.5 bg-base-content/40"
          style={"left: #{min(@state_f, 100)}%"}
          title={"Statewide: #{Float.round(@state_f, 1)}%"}
        >
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Data loading
  # ---------------------------------------------------------------------------

  # Merge school years from M-STEP snapshots and SAT results so that schools
  # which only have SAT data still appear in the year selector.
  defp load_school_years do
    mstep_years =
      MdeDistrictSnapshot
      |> Ash.Query.select([:school_year])
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.school_year)

    sat_years =
      MdeSatResult
      |> Ash.Query.select([:school_year])
      |> Ash.Query.filter(rollup_level == :district)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.school_year)

    (mstep_years ++ sat_years)
    |> Enum.uniq()
    |> Enum.sort()
  rescue
    _ -> []
  end

  # Load all entity master records with minimal fields, then group by district_code
  # to get distinct districts with building counts. Michigan has ~540 districts so
  # this fits comfortably in memory.
  defp load_entity_master_districts do
    MdeEntityMaster
    |> Ash.Query.select([:district_code, :district_official_name, :isd_official_name, :entity_type])
    |> Ash.read!(authorize?: false)
    |> Enum.group_by(& &1.district_code)
    |> Enum.flat_map(fn
      {nil, _rows} ->
        # Skip rows with no district code (ISD-level entities)
        []

      {district_code, rows} ->
        first = hd(rows)

        [
          %{
            id: district_code,
            district_code: district_code,
            district_name: first.district_official_name || district_code,
            isd_name: first.isd_official_name,
            entity_type: first.entity_type,
            buildings: length(rows),
            has_mstep: false
          }
        ]
    end)
    |> Enum.sort_by(& &1.district_name)
  rescue
    _ -> []
  end

  # Load all snapshots for a school year into a map keyed by district_code.
  defp load_snapshot_map(nil), do: %{}

  defp load_snapshot_map(year) do
    MdeDistrictSnapshot
    |> Ash.Query.for_read(:by_year, %{school_year: year})
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.district_code, &1})
  rescue
    _ -> %{}
  end

  # Overlay snapshot data onto entity master district list.
  # Districts with M-STEP snapshots get enriched data; others show entity master info.
  defp merge_districts(entity_districts, snapshot_map) do
    Enum.map(entity_districts, fn em ->
      case Map.get(snapshot_map, em.district_code) do
        nil ->
          em

        snap ->
          %{em | entity_type: snap.entity_type || em.entity_type, has_mstep: true}
      end
    end)
  end

  # Filter by search term and slice to the requested page. Stores all derived
  # state in socket assigns and resets the stream.
  defp apply_filter_and_page(socket, search, offset) do
    filtered =
      if search != "" do
        pattern = String.downcase(search)

        Enum.filter(socket.assigns.all_districts, fn d ->
          String.contains?(String.downcase(d.district_name || ""), pattern)
        end)
      else
        socket.assigns.all_districts
      end

    count = length(filtered)
    page_rows = Enum.slice(filtered, offset, @page_size)

    socket
    |> assign(:district_search, search)
    |> assign(:district_count, count)
    |> assign(:page_offset, offset)
    |> stream(:district_rows, page_rows, reset: true)
  end

  # Full row for the district detail modal (all JSONB fields included).
  # JSONB round-trip produces string-keyed maps and floats — converted here so
  # existing components (pct_badge, subject_vs_state) continue to work unchanged.
  defp snapshot_to_district_row(snapshot) do
    %{
      id: snapshot.district_code,
      district_code: snapshot.district_code,
      district_name: snapshot.district_name,
      entity_type: snapshot.entity_type,
      isd_name: snapshot.isd_name,
      buildings: snapshot.buildings || 0,
      total_assessed: snapshot.total_assessed || 0,
      ela: float_to_decimal(snapshot.ela_pct),
      math: float_to_decimal(snapshot.math_pct),
      avg_total_proficient: float_to_decimal(snapshot.avg_total_proficient),
      all_subjects: convert_snapshot_subjects(snapshot.all_subjects),
      grade_breakdown: convert_snapshot_grade_breakdown(snapshot.grade_breakdown),
      proficiency_dist: convert_snapshot_proficiency_dist(snapshot.proficiency_dist),
      has_mstep: true
    }
  end

  # Minimal row for the modal when there is no M-STEP snapshot — entity master only.
  defp entity_district_to_row(em) do
    %{
      id: em.district_code,
      district_code: em.district_code,
      district_name: em.district_name,
      entity_type: em.entity_type,
      isd_name: em.isd_name,
      buildings: em.buildings,
      total_assessed: 0,
      ela: nil,
      math: nil,
      avg_total_proficient: nil,
      all_subjects: %{},
      grade_breakdown: [],
      proficiency_dist: nil,
      has_mstep: false
    }
  end

  defp float_to_decimal(nil), do: nil
  defp float_to_decimal(f) when is_float(f), do: Decimal.from_float(f)

  defp convert_snapshot_subjects(nil), do: %{}

  defp convert_snapshot_subjects(map) do
    Map.new(map, fn {k, v} -> {k, float_to_decimal(v)} end)
  end

  defp convert_snapshot_grade_breakdown(nil), do: []

  defp convert_snapshot_grade_breakdown(list) do
    Enum.map(list, fn row ->
      %{
        grade: row["grade"],
        ela: float_to_decimal(row["ela"]),
        math: float_to_decimal(row["math"]),
        students: row["students"] || 0
      }
    end)
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

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp grade_label("11"), do: "Grade 11"
  defp grade_label(g), do: "Grade #{g}"

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
