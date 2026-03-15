defmodule EmisintWeb.Mde.EntityMasterLive do
  use EmisintWeb, :live_view

  require Ash.Query

  alias Emisint.Assessments.MdeEntityMaster

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  @empty_stats %{
    total: 0,
    active_count: 0,
    psa_count: 0,
    traditional_count: 0,
    by_type_group: %{},
    state_count: %{}
  }

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "MDE Entity Master")
      |> assign(:all_entities, [])
      |> assign(:type_groups, [])
      |> assign(:statuses, [])
      |> assign(:stats, @empty_stats)
      |> assign(:search, "")
      |> assign(:type_group_filter, "")
      |> assign(:status_filter, "")
      |> assign(:selected_entity, nil)
      |> assign(:filtered_entities, [])

    if connected?(socket) do
      all_entities = load_all_entities()

      # Use entity_type_category_name — holds meaningful values like "PSA",
      # "Traditional", "ISD", "District" across a full EntityMaster export.
      type_groups =
        all_entities
        |> Enum.map(& &1.entity_type_category_name)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.sort()

      # Derive status options from actual data rather than hardcoding.
      statuses =
        all_entities
        |> Enum.map(& &1.entity_status)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.sort()

      {:ok,
       socket
       |> assign(:all_entities, all_entities)
       |> assign(:type_groups, type_groups)
       |> assign(:statuses, statuses)
       |> assign(:stats, compute_stats(all_entities))
       |> assign(:filtered_entities, apply_filters(all_entities, "", "", ""))}
    else
      {:ok, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  def handle_event("filter", params, socket) do
    search = Map.get(params, "search", socket.assigns.search)
    type_group = Map.get(params, "type_group", socket.assigns.type_group_filter)
    status = Map.get(params, "status", socket.assigns.status_filter)

    filtered = apply_filters(socket.assigns.all_entities, search, type_group, status)

    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:type_group_filter, type_group)
     |> assign(:status_filter, status)
     |> assign(:filtered_entities, filtered)}
  end

  def handle_event("show_entity", %{"code" => code}, socket) do
    entity =
      MdeEntityMaster
      |> Ash.Query.filter(entity_code == ^code)
      |> Ash.read_one!(authorize?: false)

    {:noreply, assign(socket, :selected_entity, entity)}
  end

  def handle_event("close_entity", _params, socket) do
    {:noreply, assign(socket, :selected_entity, nil)}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-7xl mx-auto space-y-8">
        <%!-- Header --%>
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div class="flex items-center gap-4">
            <div class="p-2.5 bg-secondary/10 border border-secondary/20">
              <.icon name="hero-building-office-2" class="size-6 text-secondary" />
            </div>
            <div>
              <h1 class="text-2xl font-bold tracking-tight">MDE Entity Master</h1>
              <p class="text-sm text-base-content/50 mt-0.5">
                Michigan's complete school entity registry — ISDs, districts, PSAs, and traditional publics
              </p>
            </div>
          </div>
        </div>

        <%!-- Empty state — no data imported --%>
        <div
          :if={@all_entities == []}
          class="bg-base-100 border border-base-200 flex flex-col items-center justify-center py-24 text-center"
        >
          <div class="p-4 bg-base-200 mb-4">
            <.icon name="hero-building-office-2" class="size-10 text-base-content/20" />
          </div>
          <p class="text-base font-semibold text-base-content/50">
            No EntityMaster data imported yet
          </p>
          <p class="text-sm text-base-content/35 mt-1 max-w-xs">
            Upload the MDE EntityMaster daily CSV from the Data Import page to populate this view.
          </p>
          <.link
            navigate={~p"/admin/import"}
            class="mt-4 inline-flex items-center gap-1.5 text-sm text-secondary font-medium hover:underline"
          >
            Go to Data Import <.icon name="hero-arrow-right" class="size-4" />
          </.link>
        </div>

        <%!-- Content — only rendered when data exists --%>
        <div :if={@all_entities != []} class="space-y-6">
          <%!-- ── Summary stat cards ────────────────────────────────────────────── --%>
          <div class="grid grid-cols-2 lg:grid-cols-5 gap-2">
            <.stat_card
              label="Total Entities"
              value={format_number(@stats.total)}
              icon="hero-building-office-2"
            />
            <.stat_card
              label="Active Entities"
              value={format_number(@stats.active_count)}
              icon="hero-check-circle"
            />
            <.stat_card
              label="Traditional Public"
              value={format_number(@stats.traditional_count)}
              icon="hero-building-library"
            />
            <.stat_card
              label="State"
              value={format_number(@stats.state_count)}
              icon="hero-building-library"
            />
            <.stat_card
              label="PSAs / Charters"
              value={format_number(@stats.psa_count)}
              icon="hero-academic-cap"
            />
          </div>

          <%!-- ── Entity Category distribution chips ────────────────────────────── --%>
          <%!--
          <div :if={@stats.by_type_group != %{}} class="flex flex-wrap gap-2">
            <div
              :for={{group, count} <- Enum.sort_by(@stats.by_type_group, fn {_, v} -> v end, :desc)}
              class="flex items-center gap-1.5 px-3 py-1.5 bg-base-100 border border-base-200 text-xs"
            >
              <span class="font-medium text-base-content/70">{group || "Unknown"}</span>
              <span class="text-base-content/40">·</span>
              <span class="tabular-nums text-base-content/55">{format_number(count)}</span>
            </div>
          </div>
          -->

          <%!-- ── Filters ───────────────────────────────────────────────────────── --%>
          <div class="bg-base-100 border border-base-200 p-4">
            <form phx-change="filter" class="flex flex-col sm:flex-row gap-3">
              <%!-- Search --%>
              <div class="relative flex-1">
                <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                  <.icon name="hero-magnifying-glass" class="size-4 text-base-content/35" />
                </div>
                <input
                  type="text"
                  name="search"
                  value={@search}
                  placeholder="Search by name or entity code…"
                  class="w-full pl-9 pr-3 py-2.5 border border-base-300 bg-base-50 text-sm focus:outline-none focus:ring-2 focus:ring-secondary/25 focus:border-secondary transition-all"
                  phx-debounce="200"
                />
              </div>

              <%!-- Type category --%>
              <select
                name="type_group"
                class="border border-base-300 bg-base-50 px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-secondary/25 focus:border-secondary transition-all min-w-48"
              >
                <option value="" selected={@type_group_filter == ""}>All Entity Types</option>
                <option
                  :for={group <- @type_groups}
                  value={group}
                  selected={@type_group_filter == group}
                >
                  {group}
                </option>
              </select>

              <%!-- Status — options derived from actual data --%>
              <select
                name="status"
                class="border border-base-300 bg-base-50 px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-secondary/25 focus:border-secondary transition-all"
              >
                <option value="" selected={@status_filter == ""}>All Statuses</option>
                <option
                  :for={status <- @statuses}
                  value={status}
                  selected={@status_filter == status}
                >
                  {status}
                </option>
              </select>
            </form>

            <div class="mt-2.5 text-xs text-base-content/40">
              Showing {length(@filtered_entities)} of {format_number(@stats.total)} entities
            </div>
          </div>

          <%!-- ── Entity Table ────────────────────────────────────────────────────── --%>
          <div
            :if={@filtered_entities == []}
            class="bg-base-100 border border-base-200 flex flex-col items-center justify-center py-16 text-center"
          >
            <div class="p-3 bg-base-200 mb-3">
              <.icon name="hero-funnel" class="size-6 text-base-content/25" />
            </div>
            <p class="text-sm font-medium text-base-content/40">No entities match your filters</p>
            <p class="text-xs text-base-content/30 mt-1">
              Try adjusting the search or filter criteria.
            </p>
          </div>

          <div
            :if={@filtered_entities != []}
            class="bg-base-100 border border-base-200 overflow-hidden"
          >
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b border-base-200 bg-base-50">
                    <th class="text-left px-4 py-3 font-medium text-base-content/60 text-xs uppercase tracking-wide">
                      Code
                    </th>
                    <th class="text-left px-4 py-3 font-medium text-base-content/60 text-xs uppercase tracking-wide">
                      Entity Name
                    </th>
                    <th class="text-left px-4 py-3 font-medium text-base-content/60 text-xs uppercase tracking-wide hidden md:table-cell">
                      District
                    </th>
                    <th class="text-left px-4 py-3 font-medium text-base-content/60 text-xs uppercase tracking-wide hidden lg:table-cell">
                      ISD
                    </th>
                    <th class="text-left px-4 py-3 font-medium text-base-content/60 text-xs uppercase tracking-wide hidden sm:table-cell">
                      Type
                    </th>
                    <th class="text-left px-4 py-3 font-medium text-base-content/60 text-xs uppercase tracking-wide hidden lg:table-cell">
                      County
                    </th>
                    <th class="text-left px-4 py-3 font-medium text-base-content/60 text-xs uppercase tracking-wide hidden xl:table-cell">
                      Grades
                    </th>
                    <th class="text-left px-4 py-3 font-medium text-base-content/60 text-xs uppercase tracking-wide">
                      Status
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-base-200">
                  <tr
                    :for={entity <- @filtered_entities}
                    class="hover:bg-base-50 transition-colors cursor-pointer"
                    phx-click="show_entity"
                    phx-value-code={entity.entity_code}
                  >
                    <td class="px-4 py-3 font-mono text-xs text-base-content/60">
                      {entity.entity_code || "—"}
                    </td>
                    <td class="px-4 py-3 font-medium max-w-56 truncate">
                      {entity.entity_official_name || "—"}
                    </td>
                    <td class="px-4 py-3 text-xs text-base-content/60 hidden md:table-cell max-w-40 truncate">
                      {entity.district_official_name || "—"}
                    </td>
                    <td class="px-4 py-3 text-xs text-base-content/60 hidden lg:table-cell max-w-36 truncate">
                      {entity.isd_official_name || "—"}
                    </td>
                    <td class="px-4 py-3 text-xs text-base-content/55 hidden sm:table-cell">
                      {entity.entity_type_group_name || entity.entity_type_name || "—"}
                    </td>
                    <td class="px-4 py-3 text-xs text-base-content/55 hidden lg:table-cell">
                      {entity.entity_county_name || "—"}
                    </td>
                    <td class="px-4 py-3 text-xs text-base-content/55 hidden xl:table-cell">
                      {entity.entity_actual_grades || entity.entity_authorized_grades || "—"}
                    </td>
                    <td class="px-4 py-3">
                      <.status_badge status={entity.entity_status} />
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div
              :if={length(@filtered_entities) > 200}
              class="px-4 py-3 border-t border-base-200 text-xs text-base-content/40 text-center"
            >
              Showing first 200 of {length(@filtered_entities)} results — use filters to narrow down.
            </div>
          </div>
        </div>
      </div>

      <%!-- Entity Detail Modal --%>
      <.entity_modal :if={@selected_entity} entity={@selected_entity} />
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true

  def stat_card(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-200 p-5">
      <div class="flex items-center justify-between mb-3">
        <span class="text-xs font-medium text-base-content/40 uppercase tracking-wider">
          {@label}
        </span>
        <div class="p-1.5 bg-secondary/10">
          <.icon name={@icon} class="size-4 text-secondary" />
        </div>
      </div>
      <div class="text-3xl font-bold tracking-tight tabular-nums">{@value}</div>
    </div>
    """
  end

  attr :status, :string, default: nil

  def status_badge(assigns) do
    active? =
      is_binary(assigns.status) &&
        String.contains?(String.downcase(assigns.status), "active")

    assigns = assign(assigns, :active?, active?)

    ~H"""
    <span
      :if={not is_nil(@status) && @active?}
      class="inline-flex items-center gap-1 text-xs font-medium text-success"
    >
      <span class="inline-block size-1.5 rounded-full bg-success"></span>
      {@status}
    </span>
    <span
      :if={not is_nil(@status) && !@active?}
      class="inline-flex items-center gap-1 text-xs font-medium text-base-content/35"
    >
      <span class="inline-block size-1.5 rounded-full bg-base-300"></span>
      {@status}
    </span>
    <span :if={is_nil(@status)} class="text-xs text-base-content/30">—</span>
    """
  end

  attr :entity, :any, required: true

  def entity_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_entity"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="close_entity"></div>

      <div class="relative bg-base-100 w-full max-w-3xl max-h-[90vh] overflow-y-auto shadow-2xl border border-base-200">
        <%!-- Sticky header --%>
        <div class="sticky top-0 bg-base-100 border-b border-base-200 px-6 py-4 flex items-start justify-between gap-4 z-10">
          <div>
            <div class="flex items-center gap-2 flex-wrap">
              <h2 class="text-lg font-bold leading-tight">
                {@entity.entity_official_name || @entity.entity_code}
              </h2>
              <.status_badge status={@entity.entity_status} />
            </div>
            <div class="flex flex-wrap items-center gap-x-2 gap-y-0.5 mt-1 text-xs text-base-content/50">
              <span class="font-mono">{@entity.entity_code}</span>
              <span :if={@entity.entity_type_group_name}>·</span>
              <span :if={@entity.entity_type_group_name}>{@entity.entity_type_group_name}</span>
              <span :if={@entity.entity_county_name}>·</span>
              <span :if={@entity.entity_county_name}>{@entity.entity_county_name} County</span>
            </div>
          </div>
          <button
            phx-click="close_entity"
            class="p-1.5 text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors shrink-0"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="p-6 space-y-6">
          <%!-- ISD & District --%>
          <.detail_section title="ISD & District">
            <.detail_row label="ISD Code" value={@entity.isd_code} />
            <.detail_row label="ISD Name" value={@entity.isd_official_name} />
            <.detail_row label="District Code" value={@entity.district_code} />
            <.detail_row label="District Official Name" value={@entity.district_official_name} />
            <.detail_row label="District Common Name" value={@entity.district_common_name} />
            <.detail_row label="District Type" value={@entity.district_type} />
            <.detail_row label="District Type Name" value={@entity.district_type_name} />
          </.detail_section>

          <%!-- Entity Identity --%>
          <.detail_section title="Entity Identity">
            <.detail_row label="Entity Code" value={@entity.entity_code} mono />
            <.detail_row label="Official Name" value={@entity.entity_official_name} />
            <.detail_row label="Agreement Number" value={@entity.agreement_number} />
            <.detail_row label="Entity Type" value={@entity.entity_type} />
            <.detail_row label="Entity Type Name" value={@entity.entity_type_name} />
            <.detail_row label="Type Group" value={@entity.entity_type_group} />
            <.detail_row label="Type Group Name" value={@entity.entity_type_group_name} />
            <.detail_row label="Type Category" value={@entity.entity_type_category} />
            <.detail_row label="Type Category Name" value={@entity.entity_type_category_name} />
          </.detail_section>

          <%!-- Educational Settings & Grades --%>
          <.detail_section title="Educational Settings & Grades">
            <.detail_row label="Status" value={@entity.entity_status} />
            <.detail_row label="Open Date" value={@entity.entity_open_date} />
            <.detail_row label="Close Date" value={@entity.entity_close_date} />
            <.detail_row
              label="Authorized Settings"
              value={@entity.entity_authorized_educational_settings}
            />
            <.detail_row
              label="Actual Settings"
              value={@entity.entity_actual_educational_settings}
            />
            <.detail_row label="Authorized Grades" value={@entity.entity_authorized_grades} />
            <.detail_row label="Actual Grades" value={@entity.entity_actual_grades} />
          </.detail_section>

          <%!-- Geography --%>
          <.detail_section title="Geography">
            <.detail_row label="County Code" value={@entity.entity_county_code} />
            <.detail_row label="County Name" value={@entity.entity_county_name} />
            <.detail_row label="Chartering Agency Code" value={@entity.entity_chartering_agency_code} />
            <.detail_row label="Chartering Agency Name" value={@entity.entity_chartering_agency_name} />
            <.detail_row
              label="Geographic LEA District Code"
              value={@entity.entity_geographic_lea_district_code}
            />
            <.detail_row
              label="Geographic LEA District Name"
              value={@entity.entity_geographic_lea_district_official_name}
            />
            <.detail_row label="NCES Code" value={@entity.entity_nces_code} mono />
            <.detail_row label="Locale Code" value={@entity.entity_locale_code} />
            <.detail_row label="Locale Name" value={@entity.entity_locale_name} />
            <.detail_row label="FIPS Code" value={@entity.entity_fips_code} mono />
            <.detail_row label="REMC Id" value={@entity.entity_remc_id} />
          </.detail_section>

          <%!-- Programs & Services --%>
          <.detail_section title="Programs & Services">
            <.detail_row label="Schedules List" value={@entity.entity_schedules_list} />
            <.detail_row
              label="Early Childhood Programs"
              value={@entity.entity_early_childhood_program_list}
            />
            <.detail_row
              label="Transportation From (Code)"
              value={@entity.receives_transportation_from_code}
            />
            <.detail_row
              label="Transportation From (Name)"
              value={@entity.receives_transportation_from_name}
            />
            <.detail_row
              label="Religious Orientation Code"
              value={@entity.entity_religious_orientation_code}
            />
            <.detail_row
              label="Religious Orientation Name"
              value={@entity.entity_religious_orientation_name}
            />
            <.detail_row label="Early Middle College" value={@entity.early_middle_college} />
            <.detail_row label="SEE Type" value={@entity.see_type} />
            <.detail_row label="Head Start Grantee" value={@entity.head_start_grantee} />
            <.detail_row label="School Emphasis" value={@entity.school_emphasis} />
            <.detail_row label="ESSA Support Category" value={@entity.essa_support_category_status} />
          </.detail_section>

          <%!-- Leadership --%>
          <.detail_section title="Leadership">
            <.detail_row label="Honorific" value={@entity.entity_lead_admin_honorific} />
            <.detail_row label="First Name" value={@entity.entity_lead_admin_first_name} />
            <.detail_row label="Last Name" value={@entity.entity_lead_admin_last_name} />
          </.detail_section>

          <%!-- Contact --%>
          <.detail_section title="Contact">
            <.detail_row label="Email" value={@entity.entity_email} />
            <.detail_row label="Phone" value={phone_display(@entity)} />
            <.detail_row label="Fax" value={fax_display(@entity)} />
          </.detail_section>

          <%!-- Physical Address --%>
          <.detail_section title="Physical Address">
            <.detail_row label="Street" value={@entity.entity_physical_street} />
            <.detail_row label="City" value={@entity.entity_physical_city} />
            <.detail_row label="State" value={@entity.entity_physical_state} />
            <.detail_row label="Zip" value={@entity.entity_physical_zip4} />
          </.detail_section>

          <%!-- Mailing Address --%>
          <.detail_section title="Mailing Address">
            <.detail_row label="Street" value={@entity.entity_mailing_street} />
            <.detail_row label="City" value={@entity.entity_mailing_city} />
            <.detail_row label="State" value={@entity.entity_mailing_state} />
            <.detail_row label="Zip" value={@entity.entity_mailing_zip4} />
          </.detail_section>
        </div>
      </div>
    </div>
    """
  end

  slot :inner_block, required: true
  attr :title, :string, required: true

  def detail_section(assigns) do
    ~H"""
    <div class="space-y-1">
      <div class="flex items-center gap-2 mb-2">
        <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
          {@title}
        </h3>
        <div class="flex-1 h-px bg-base-200"></div>
      </div>
      <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-1">
        {render_slot(@inner_block)}
      </dl>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, default: nil
  attr :mono, :boolean, default: false

  def detail_row(assigns) do
    ~H"""
    <div :if={not is_nil(@value)} class="flex items-baseline gap-2 py-1">
      <dt class="text-xs text-base-content/45 shrink-0 w-36">{@label}</dt>
      <dd class={["text-xs font-medium break-all", @mono && "font-mono"]}>{@value}</dd>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Data loading
  # ---------------------------------------------------------------------------

  # List columns only — full entity is lazy-loaded on detail click.
  @list_columns [
    :entity_code,
    :entity_official_name,
    :district_official_name,
    :isd_official_name,
    :entity_type_group_name,
    :entity_type_name,
    :entity_county_name,
    :entity_actual_grades,
    :entity_authorized_grades,
    :entity_status,
    :entity_type_category_name
  ]

  defp load_all_entities do
    MdeEntityMaster
    |> Ash.Query.select(@list_columns)
    |> Ash.Query.sort([:entity_official_name])
    |> Ash.read!(authorize?: false)
  end

  # ---------------------------------------------------------------------------
  # Filtering (in-memory — ~4–5k records is fast enough)
  # ---------------------------------------------------------------------------

  defp apply_filters(entities, search, type_group, status) do
    search_down = String.downcase(String.trim(search))

    entities
    |> filter_by_search(search_down)
    |> filter_by_type_group(type_group)
    |> filter_by_status(status)
    |> Enum.take(200)
  end

  defp filter_by_search(entities, ""), do: entities

  defp filter_by_search(entities, search) do
    Enum.filter(entities, fn e ->
      name_match =
        e.entity_official_name &&
          String.contains?(String.downcase(e.entity_official_name), search)

      code_match =
        e.entity_code && String.contains?(String.downcase(e.entity_code), search)

      district_match =
        e.district_official_name &&
          String.contains?(String.downcase(e.district_official_name), search)

      name_match || code_match || district_match
    end)
  end

  defp filter_by_type_group(entities, ""), do: entities

  defp filter_by_type_group(entities, group) do
    Enum.filter(entities, &(&1.entity_type_category_name == group))
  end

  defp filter_by_status(entities, ""), do: entities

  defp filter_by_status(entities, status) do
    Enum.filter(entities, &(&1.entity_status == status))
  end

  # ---------------------------------------------------------------------------
  # Stats
  # ---------------------------------------------------------------------------

  defp open_active?(e),
    do: is_binary(e.entity_status) && String.downcase(e.entity_status) == "open-active"

  defp compute_stats(entities) do
    total = length(entities)

    # "Open-Active", "Active", etc. — any status containing "active"
    active_count =
      Enum.count(entities, fn e ->
        is_binary(e.entity_status) &&
          String.contains?(String.downcase(e.entity_status), "open-active")
      end)

    # entity_type_category_name holds "PSA", "Traditional", "ISD", "District", etc.
    # Only count Open-Active entities in the distribution chips.
    by_type_group =
      entities
      |> Enum.filter(&open_active?/1)
      |> Enum.group_by(& &1.entity_type_category_name)
      |> Map.new(fn {k, v} -> {k || "Unknown", length(v)} end)

    psa_count =
      Enum.count(entities, fn e ->
        c = e.entity_type_category_name
        open_active?(e) && c && String.contains?(String.downcase(c), "psa")
      end)

    traditional_count =
      Enum.count(entities, fn e ->
        c = e.entity_type_category_name
        open_active?(e) && c && String.contains?(String.downcase(c), "lea")
      end)

    state_count =
      Enum.count(entities, fn e ->
        c = e.entity_type_category_name
        open_active?(e) && c && String.contains?(String.downcase(c), "state")
      end)

    %{
      total: total,
      active_count: active_count,
      psa_count: psa_count,
      traditional_count: traditional_count,
      state_count: state_count,
      by_type_group: by_type_group
    }
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp phone_display(e) do
    case {e.entity_phone, e.entity_phone_ext} do
      {nil, _} -> nil
      {phone, nil} -> phone
      {phone, ext} -> "#{phone} x#{ext}"
    end
  end

  defp fax_display(e) do
    case {e.entity_fax, e.entity_fax_ext} do
      {nil, _} -> nil
      {fax, nil} -> fax
      {fax, ext} -> "#{fax} x#{ext}"
    end
  end

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
