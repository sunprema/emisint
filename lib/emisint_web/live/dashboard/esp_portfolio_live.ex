defmodule EmisintWeb.Dashboard.EspPortfolioLive do
  use EmisintWeb, :live_view

  import Ecto.Query, only: [from: 2]

  require Ash.Query

  alias Emisint.Assessments.MdeEmoContact
  alias Emisint.Assessments.MdeEntityMaster
  alias Emisint.Repo

  on_mount {EmisintWeb.LiveUserAuth, :live_user_required}
  on_mount {EmisintWeb.LiveScope, :default}

  @stats_years ["24 - 25 School Year", "22 - 23 School Year"]

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "ESP Portfolio")
      |> assign(:emo_list, [])
      |> assign(:selected_emo, nil)
      |> assign(:schools, [])
      |> assign(:emo_search, "")
      |> assign(:filtered_emos, [])
      |> assign(:school_search, "")
      |> assign(:filtered_schools, [])
      |> assign(:active_tab, :schools)
      |> assign(:stats_years, @stats_years)
      |> assign(:stats_year, hd(@stats_years))
      |> assign(:portfolio_stats, [])
      |> assign(:sat_portfolio_stats, [])

    if connected?(socket) do
      emos = load_emo_list()

      {:ok,
       socket
       |> assign(:emo_list, emos)
       |> assign(:filtered_emos, emos)}
    else
      {:ok, socket}
    end
  end

  def handle_params(%{"emo" => emo_name}, _uri, socket) do
    emo = Enum.find(socket.assigns.emo_list, &(&1.name == emo_name))

    if emo do
      {schools, contact_map} = load_schools_for_emo(emo_name)
      building_codes = Enum.map(schools, & &1.entity_code) |> Enum.reject(&is_nil/1)
      year = socket.assigns.stats_year
      stats = load_portfolio_stats(building_codes, year)
      sat_stats = load_sat_portfolio_stats(building_codes, year)

      {:noreply,
       socket
       |> assign(:selected_emo, emo)
       |> assign(:schools, schools)
       |> assign(:contact_map, contact_map)
       |> assign(:school_search, "")
       |> assign(:filtered_schools, schools)
       |> assign(:portfolio_stats, stats)
       |> assign(:sat_portfolio_stats, sat_stats)}
    else
      {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:selected_emo, nil)
     |> assign(:schools, [])
     |> assign(:contact_map, %{})
     |> assign(:school_search, "")
     |> assign(:filtered_schools, [])
     |> assign(:active_tab, :schools)
     |> assign(:portfolio_stats, [])
     |> assign(:sat_portfolio_stats, [])}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  def handle_event("search_emos", %{"value" => search}, socket) do
    filtered = filter_emos(socket.assigns.emo_list, search)

    {:noreply,
     socket
     |> assign(:emo_search, search)
     |> assign(:filtered_emos, filtered)}
  end

  def handle_event("clear_emo_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:emo_search, "")
     |> assign(:filtered_emos, socket.assigns.emo_list)}
  end

  def handle_event("search_schools", %{"value" => search}, socket) do
    filtered = filter_schools(socket.assigns.schools, search)

    {:noreply,
     socket
     |> assign(:school_search, search)
     |> assign(:filtered_schools, filtered)}
  end

  def handle_event("clear_school_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:school_search, "")
     |> assign(:filtered_schools, socket.assigns.schools)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

  def handle_event("select_stats_year", %{"year" => year}, socket) do
    building_codes =
      Enum.map(socket.assigns.schools, & &1.entity_code) |> Enum.reject(&is_nil/1)

    stats = load_portfolio_stats(building_codes, year)
    sat_stats = load_sat_portfolio_stats(building_codes, year)

    {:noreply,
     socket
     |> assign(:stats_year, year)
     |> assign(:portfolio_stats, stats)
     |> assign(:sat_portfolio_stats, sat_stats)}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  def render(assigns) do
    assigns = Map.put_new(assigns, :contact_map, %{})

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-7xl mx-auto space-y-6">
        <%!-- Page header --%>
        <div class="flex items-center gap-4">
          <div class="p-2.5 bg-secondary/10 border border-secondary/20">
            <.icon name="hero-briefcase" class="size-6 text-secondary" />
          </div>
          <div>
            <h1 class="text-2xl font-bold tracking-tight">ESP Portfolio</h1>
            <p class="text-sm text-base-content/50 mt-0.5">
              Browse schools by Education Service Provider / Management Organization
            </p>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">
          <%!-- Left panel: EMO list --%>
          <div class="lg:col-span-1 bg-base-100 border border-base-200 overflow-hidden flex flex-col">
            <div class="px-4 py-3 border-b border-base-200">
              <div class="flex items-center justify-between mb-2">
                <h2 class="font-semibold text-sm">Management Organizations</h2>
                <span class="badge badge-ghost badge-sm">{length(@filtered_emos)}</span>
              </div>
              <div class="relative">
                <input
                  type="text"
                  placeholder="Search ESPs…"
                  value={@emo_search}
                  phx-keyup="search_emos"
                  phx-debounce="150"
                  name="search"
                  class="w-full pl-8 pr-8 py-1.5 text-xs border border-base-300 bg-base-50 focus:outline-none focus:ring-1 focus:ring-secondary/30 focus:border-secondary transition-all"
                />
                <.icon
                  name="hero-magnifying-glass"
                  class="absolute left-2 top-1/2 -translate-y-1/2 size-3.5 text-base-content/30"
                />
                <button
                  :if={@emo_search != ""}
                  phx-click="clear_emo_search"
                  class="absolute right-2 top-1/2 -translate-y-1/2 text-base-content/30 hover:text-base-content transition-colors"
                >
                  <.icon name="hero-x-mark" class="size-3.5" />
                </button>
              </div>
            </div>

            <%!-- Empty state --%>
            <div
              :if={@emo_list == []}
              class="flex flex-col items-center justify-center py-16 text-center px-4"
            >
              <div class="p-3 bg-base-200 mb-3">
                <.icon name="hero-briefcase" class="size-6 text-base-content/25" />
              </div>
              <p class="text-sm font-medium text-base-content/40">No ESPs found</p>
              <p class="text-xs text-base-content/30 mt-1">
                Import the EMO Contact list CSV to populate this list.
              </p>
            </div>

            <%!-- No search results --%>
            <div
              :if={@emo_list != [] && @filtered_emos == []}
              class="flex flex-col items-center justify-center py-12 text-center px-4"
            >
              <p class="text-sm text-base-content/40">No ESPs match "{@emo_search}"</p>
            </div>

            <%!-- EMO list --%>
            <div
              :if={@filtered_emos != []}
              class="divide-y divide-base-200 overflow-y-auto max-h-[calc(100vh-280px)]"
            >
              <button
                :for={emo <- @filtered_emos}
                phx-click={JS.patch(~p"/esp-portfolio?emo=#{emo.name}")}
                class={[
                  "w-full text-left px-4 py-3 hover:bg-base-50 transition-colors flex items-start justify-between gap-2",
                  @selected_emo && @selected_emo.name == emo.name &&
                    "bg-secondary/5 border-l-2 border-secondary"
                ]}
              >
                <div class="min-w-0 flex-1">
                  <p class={[
                    "text-sm font-medium leading-snug",
                    @selected_emo && @selected_emo.name == emo.name && "text-secondary"
                  ]}>
                    {emo.name}
                  </p>
                </div>
                <span class="badge badge-ghost badge-xs shrink-0 mt-0.5">
                  {emo.school_count}
                </span>
              </button>
            </div>
          </div>

          <%!-- Right panel --%>
          <div class="lg:col-span-2 bg-base-100 border border-base-200 overflow-hidden">
            <%!-- No EMO selected --%>
            <div
              :if={is_nil(@selected_emo)}
              class="flex flex-col items-center justify-center py-24 text-center px-6"
            >
              <div class="p-4 bg-base-200 mb-4">
                <.icon name="hero-cursor-arrow-ripple" class="size-8 text-base-content/20" />
              </div>
              <p class="text-base font-medium text-base-content/40">Select a management organization</p>
              <p class="text-sm text-base-content/30 mt-1">
                Choose an ESP on the left to view its portfolio of schools.
              </p>
            </div>

            <%!-- EMO selected --%>
            <div :if={@selected_emo}>
              <%!-- EMO header --%>
              <div class="px-6 py-4 border-b border-base-200">
                <div class="flex items-start justify-between gap-4">
                  <div>
                    <div class="flex items-center gap-2">
                      <h2 class="font-semibold">{@selected_emo.name}</h2>
                      <span class="badge badge-secondary badge-sm">ESP</span>
                    </div>
                    <p class="text-xs text-base-content/40 mt-0.5">
                      {@selected_emo.school_count} school{if @selected_emo.school_count != 1, do: "s", else: ""}
                    </p>
                  </div>
                </div>
              </div>

              <%!-- Tabs --%>
              <div class="flex border-b border-base-200 bg-base-50/50">
                <button
                  phx-click="switch_tab"
                  phx-value-tab="schools"
                  class={[
                    "px-5 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors",
                    if(@active_tab == :schools,
                      do: "border-secondary text-secondary bg-base-100",
                      else: "border-transparent text-base-content/50 hover:text-base-content hover:border-base-300"
                    )
                  ]}
                >
                  <div class="flex items-center gap-2">
                    <.icon name="hero-list-bullet" class="size-3.5" /> Schools
                    <span class="badge badge-ghost badge-xs">{length(@schools)}</span>
                  </div>
                </button>
                <button
                  phx-click="switch_tab"
                  phx-value-tab="dashboard"
                  class={[
                    "px-5 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors",
                    if(@active_tab == :dashboard,
                      do: "border-secondary text-secondary bg-base-100",
                      else: "border-transparent text-base-content/50 hover:text-base-content hover:border-base-300"
                    )
                  ]}
                >
                  <div class="flex items-center gap-2">
                    <.icon name="hero-chart-bar" class="size-3.5" /> M-STEP Dashboard
                  </div>
                </button>
                <button
                  phx-click="switch_tab"
                  phx-value-tab="sat_dashboard"
                  class={[
                    "px-5 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors",
                    if(@active_tab == :sat_dashboard,
                      do: "border-secondary text-secondary bg-base-100",
                      else: "border-transparent text-base-content/50 hover:text-base-content hover:border-base-300"
                    )
                  ]}
                >
                  <div class="flex items-center gap-2">
                    <.icon name="hero-chart-bar" class="size-3.5" /> SAT Dashboard
                  </div>
                </button>
              </div>

              <%!-- Tab: Schools --%>
              <div :if={@active_tab == :schools}>
                <div class="px-6 py-3 border-b border-base-200 flex items-center gap-3">
                  <div class="relative flex-1">
                    <input
                      type="text"
                      placeholder="Filter schools…"
                      value={@school_search}
                      phx-keyup="search_schools"
                      phx-debounce="150"
                      name="school_search"
                      class="w-full pl-8 pr-8 py-1.5 text-xs border border-base-300 bg-base-50 focus:outline-none focus:ring-1 focus:ring-secondary/30 focus:border-secondary transition-all"
                    />
                    <.icon
                      name="hero-magnifying-glass"
                      class="absolute left-2 top-1/2 -translate-y-1/2 size-3.5 text-base-content/30"
                    />
                    <button
                      :if={@school_search != ""}
                      phx-click="clear_school_search"
                      class="absolute right-2 top-1/2 -translate-y-1/2 text-base-content/30 hover:text-base-content transition-colors"
                    >
                      <.icon name="hero-x-mark" class="size-3.5" />
                    </button>
                  </div>
                  <.link
                    patch={~p"/esp-portfolio"}
                    class="text-xs text-base-content/40 hover:text-base-content transition-colors flex items-center gap-1 shrink-0"
                  >
                    <.icon name="hero-x-mark" class="size-3.5" /> Clear
                  </.link>
                </div>

                <%!-- No filter results --%>
                <div
                  :if={@schools != [] && @filtered_schools == []}
                  class="flex flex-col items-center justify-center py-12 text-center px-6"
                >
                  <p class="text-sm text-base-content/40">No schools match "{@school_search}"</p>
                </div>

                <%!-- Schools table --%>
                <div :if={@filtered_schools != []} class="overflow-x-auto">
                  <table class="table table-sm w-full">
                    <thead>
                      <tr class="text-xs text-base-content/50 border-b border-base-200">
                        <th class="px-4 py-3 font-medium text-left">School</th>
                        <th class="px-4 py-3 font-medium text-left">District Code</th>
                        <th class="px-4 py-3 font-medium text-left">County</th>
                        <th class="px-4 py-3 font-medium text-left">Grades</th>
                        <th class="px-4 py-3 font-medium text-left">Contact</th>
                        <th class="px-4 py-3 w-8"></th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-base-200">
                      <tr
                        :for={school <- @filtered_schools}
                        class={[
                          "transition-colors",
                          if(school.district_code,
                            do: "hover:bg-secondary/5 cursor-pointer",
                            else: "hover:bg-base-50"
                          )
                        ]}
                        phx-click={school.district_code && JS.navigate(~p"/mde/districts/#{school.district_code}?from=esp&emo=#{@selected_emo.name}")}
                      >
                        <td class="px-4 py-3">
                          <p class="text-sm font-medium leading-snug">
                            {school.entity_official_name}
                          </p>
                          <p class="text-xs text-base-content/40 mt-0.5">
                            {school.entity_code}
                          </p>
                        </td>
                        <td class="px-4 py-3 text-sm text-base-content/70">
                          {school.district_code || "—"}
                        </td>
                        <td class="px-4 py-3 text-sm text-base-content/70">
                          {school.entity_county_name || "—"}
                        </td>
                        <td class="px-4 py-3 text-xs text-base-content/60">
                          {school.entity_actual_grades || school.entity_authorized_grades || "—"}
                        </td>
                        <td class="px-4 py-3">
                          <%= if contact = Map.get(@contact_map, school.district_code) do %>
                            <p class="text-xs text-base-content/70">{contact.contact_name}</p>
                            <span
                              :if={contact.contact_email}
                              class="text-xs text-secondary/80"
                            >
                              {contact.contact_email}
                            </span>
                          <% else %>
                            <span class="text-xs text-base-content/30">—</span>
                          <% end %>
                        </td>
                        <td class="px-4 py-3 text-base-content/25">
                          <.icon :if={school.district_code} name="hero-chevron-right" class="size-4" />
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>

                <%!-- No schools --%>
                <div
                  :if={@schools == []}
                  class="flex flex-col items-center justify-center py-16 text-center px-6"
                >
                  <div class="p-3 bg-base-200 mb-3">
                    <.icon name="hero-academic-cap" class="size-6 text-base-content/25" />
                  </div>
                  <p class="text-sm font-medium text-base-content/40">No schools found</p>
                  <p class="text-xs text-base-content/30 mt-1">
                    No Open-Active entities found for this ESP's district codes.
                  </p>
                </div>
              </div>

              <%!-- Tab: M-STEP Dashboard --%>
              <div :if={@active_tab == :dashboard}>
                <.portfolio_dashboard
                  stats={@portfolio_stats}
                  stats_year={@stats_year}
                  stats_years={@stats_years}
                />
              </div>

              <%!-- Tab: SAT Dashboard --%>
              <div :if={@active_tab == :sat_dashboard}>
                <.sat_dashboard
                  stats={@sat_portfolio_stats}
                  stats_year={@stats_year}
                  stats_years={@stats_years}
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Dashboard components (mirrors portfolio_live.ex)
  # ---------------------------------------------------------------------------

  attr :stats, :list, required: true
  attr :stats_year, :string, required: true
  attr :stats_years, :list, required: true

  defp portfolio_dashboard(assigns) do
    exceeds = Enum.count(assigns.stats, fn s -> not s.no_lea_found and (s.delta || 0) > 0 end)
    below = Enum.count(assigns.stats, fn s -> not s.no_lea_found and (s.delta || 0) <= 0 end)
    no_data = Enum.count(assigns.stats, fn s -> s.no_lea_found end)
    total_comparable = exceeds + below

    max_abs_delta =
      assigns.stats
      |> Enum.reject(& &1.no_lea_found)
      |> Enum.map(fn s -> abs(s.delta || 0) end)
      |> Enum.max(fn -> 1.0 end)

    max_abs_delta = if max_abs_delta == 0, do: 1.0, else: max_abs_delta

    assigns =
      assigns
      |> Map.put(:exceeds, exceeds)
      |> Map.put(:below, below)
      |> Map.put(:no_data, no_data)
      |> Map.put(:total_comparable, total_comparable)
      |> Map.put(:max_abs_delta, max_abs_delta)

    ~H"""
    <div class="bg-base-50/50">
      <div class="px-6 pt-4 pb-3 flex items-center justify-between gap-4">
        <div>
          <h3 class="text-sm font-semibold">M-STEP / PSAT All Subjects — vs. Geographic LEA</h3>
          <p class="text-xs text-base-content/40 mt-0.5">Schools exceeding their local district average</p>
        </div>
        <select phx-change="select_stats_year" name="year" class="select select-xs select-bordered text-xs">
          <option :for={y <- @stats_years} value={y} selected={y == @stats_year}>{y}</option>
        </select>
      </div>

      <div class="px-6 pb-4 grid grid-cols-3 gap-3">
        <div class="bg-base-100 border border-base-200 px-4 py-3 flex flex-col gap-1">
          <span class="text-xs text-base-content/40 font-medium">Exceeds LEA</span>
          <div class="flex items-end gap-2">
            <span class="text-2xl font-bold text-success">{@exceeds}</span>
            <span class="text-xs text-base-content/40 mb-0.5">
              {if @total_comparable > 0, do: "#{round(@exceeds / @total_comparable * 100)}%", else: "—"}
            </span>
          </div>
        </div>
        <div class="bg-base-100 border border-base-200 px-4 py-3 flex flex-col gap-1">
          <span class="text-xs text-base-content/40 font-medium">Below LEA</span>
          <div class="flex items-end gap-2">
            <span class="text-2xl font-bold text-error">{@below}</span>
            <span class="text-xs text-base-content/40 mb-0.5">
              {if @total_comparable > 0, do: "#{round(@below / @total_comparable * 100)}%", else: "—"}
            </span>
          </div>
        </div>
        <div class="bg-base-100 border border-base-200 px-4 py-3 flex flex-col gap-1">
          <span class="text-xs text-base-content/40 font-medium">No LEA Data</span>
          <div class="flex items-end gap-2">
            <span class="text-2xl font-bold text-base-content/30">{@no_data}</span>
          </div>
        </div>
      </div>

      <div :if={@total_comparable > 0} class="px-6 pb-4">
        <div class="flex h-2 overflow-hidden bg-base-200 gap-px">
          <div class="bg-success transition-all duration-500" style={"width: #{round(@exceeds / @total_comparable * 100)}%"} />
          <div class="bg-error transition-all duration-500" style={"width: #{round(@below / @total_comparable * 100)}%"} />
        </div>
        <div class="flex justify-between mt-1">
          <span class="text-[10px] text-success font-medium">Exceeds</span>
          <span class="text-[10px] text-error font-medium">Below</span>
        </div>
      </div>

      <div :if={@stats == []} class="px-6 pb-4 text-xs text-base-content/30 italic">
        No M-STEP / PSAT data found for this year.
      </div>

      <div :if={@stats != []} class="px-6 pb-5 space-y-2">
        <p class="text-[10px] text-base-content/30 uppercase tracking-wide font-medium">
          School vs LEA delta (pp) — sorted best to worst
        </p>
        <div class="space-y-1.5">
          <div :for={s <- Enum.reject(@stats, & &1.no_lea_found)} class="flex items-center gap-3 group">
            <div class="w-40 shrink-0 truncate text-xs text-base-content/60 group-hover:text-base-content transition-colors text-right leading-tight">
              {short_name(s.school_name)}
            </div>
            <div class="flex-1 flex items-center gap-1 min-w-0">
              <div class="relative flex-1 h-4 flex items-center">
                <div class="absolute left-1/2 top-0 bottom-0 w-px bg-base-300 z-10" />
                <div
                  class={["absolute h-3 transition-all duration-300", if((s.delta || 0) >= 0, do: "bg-success/70 left-1/2", else: "bg-error/70 right-1/2")]}
                  style={"width: #{min(abs(s.delta || 0) / @max_abs_delta * 50, 50)}%"}
                />
              </div>
            </div>
            <div class={["text-xs font-mono font-semibold w-14 shrink-0 text-right", if((s.delta || 0) >= 0, do: "text-success", else: "text-error")]}>
              {if (s.delta || 0) >= 0, do: "+", else: ""}{format_delta(s.delta)}pp
            </div>
          </div>
        </div>
        <div :if={@no_data > 0} class="mt-3 border border-base-200 overflow-hidden">
          <div class="px-3 py-2 bg-base-200/50 border-b border-base-200">
            <p class="text-[10px] text-base-content/40 uppercase tracking-wide font-medium">
              {@no_data} school{if @no_data != 1, do: "s", else: ""} excluded — no geographic LEA match
            </p>
          </div>
          <table class="w-full">
            <tbody>
              <tr :for={s <- Enum.filter(@stats, & &1.no_lea_found)} class="border-b border-base-200 last:border-0">
                <td class="px-3 py-1.5 text-xs text-base-content/40">{s.school_name}</td>
                <td class="px-3 py-1.5 text-xs font-mono text-base-content/30 text-right">{s.building_code}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  attr :stats, :list, required: true
  attr :stats_year, :string, required: true
  attr :stats_years, :list, required: true

  defp sat_dashboard(assigns) do
    exceeds = Enum.count(assigns.stats, fn s -> not s.no_lea_found and (s.delta || 0) > 0 end)
    below = Enum.count(assigns.stats, fn s -> not s.no_lea_found and (s.delta || 0) <= 0 end)
    no_data = Enum.count(assigns.stats, fn s -> s.no_lea_found end)
    total_comparable = exceeds + below

    max_abs_delta =
      assigns.stats
      |> Enum.reject(& &1.no_lea_found)
      |> Enum.map(fn s -> abs(s.delta || 0) end)
      |> Enum.max(fn -> 1.0 end)

    max_abs_delta = if max_abs_delta == 0, do: 1.0, else: max_abs_delta

    assigns =
      assigns
      |> Map.put(:exceeds, exceeds)
      |> Map.put(:below, below)
      |> Map.put(:no_data, no_data)
      |> Map.put(:total_comparable, total_comparable)
      |> Map.put(:max_abs_delta, max_abs_delta)

    ~H"""
    <div class="bg-base-50/50">
      <div class="px-6 pt-4 pb-3 flex items-center justify-between gap-4">
        <div>
          <h3 class="text-sm font-semibold">SAT College Readiness — All Score vs. Geographic LEA</h3>
          <p class="text-xs text-base-content/40 mt-0.5">Schools exceeding their local district combined SAT score (Math + EBRW)</p>
        </div>
        <select phx-change="select_stats_year" name="year" class="select select-xs select-bordered text-xs">
          <option :for={y <- @stats_years} value={y} selected={y == @stats_year}>{y}</option>
        </select>
      </div>

      <div class="px-6 pb-4 grid grid-cols-3 gap-3">
        <div class="bg-base-100 border border-base-200 px-4 py-3 flex flex-col gap-1">
          <span class="text-xs text-base-content/40 font-medium">Exceeds LEA</span>
          <div class="flex items-end gap-2">
            <span class="text-2xl font-bold text-success">{@exceeds}</span>
            <span class="text-xs text-base-content/40 mb-0.5">
              {if @total_comparable > 0, do: "#{round(@exceeds / @total_comparable * 100)}%", else: "—"}
            </span>
          </div>
        </div>
        <div class="bg-base-100 border border-base-200 px-4 py-3 flex flex-col gap-1">
          <span class="text-xs text-base-content/40 font-medium">Below LEA</span>
          <div class="flex items-end gap-2">
            <span class="text-2xl font-bold text-error">{@below}</span>
            <span class="text-xs text-base-content/40 mb-0.5">
              {if @total_comparable > 0, do: "#{round(@below / @total_comparable * 100)}%", else: "—"}
            </span>
          </div>
        </div>
        <div class="bg-base-100 border border-base-200 px-4 py-3 flex flex-col gap-1">
          <span class="text-xs text-base-content/40 font-medium">No LEA Data</span>
          <div class="flex items-end gap-2">
            <span class="text-2xl font-bold text-base-content/30">{@no_data}</span>
          </div>
        </div>
      </div>

      <div :if={@total_comparable > 0} class="px-6 pb-4">
        <div class="flex h-2 overflow-hidden bg-base-200 gap-px">
          <div class="bg-success transition-all duration-500" style={"width: #{round(@exceeds / @total_comparable * 100)}%"} />
          <div class="bg-error transition-all duration-500" style={"width: #{round(@below / @total_comparable * 100)}%"} />
        </div>
        <div class="flex justify-between mt-1">
          <span class="text-[10px] text-success font-medium">Exceeds</span>
          <span class="text-[10px] text-error font-medium">Below</span>
        </div>
      </div>

      <div :if={@stats == []} class="px-6 pb-4 text-xs text-base-content/30 italic">
        No SAT data found for this year.
      </div>

      <div :if={@stats != []} class="px-6 pb-5 space-y-2">
        <p class="text-[10px] text-base-content/30 uppercase tracking-wide font-medium">
          School vs LEA delta (pts) — sorted best to worst
        </p>
        <div class="space-y-1.5">
          <div :for={s <- Enum.reject(@stats, & &1.no_lea_found)} class="flex items-center gap-3 group">
            <div class="w-40 shrink-0 truncate text-xs text-base-content/60 group-hover:text-base-content transition-colors text-right leading-tight">
              {short_name(s.school_name)}
            </div>
            <div class="flex-1 flex items-center gap-1 min-w-0">
              <div class="relative flex-1 h-4 flex items-center">
                <div class="absolute left-1/2 top-0 bottom-0 w-px bg-base-300 z-10" />
                <div
                  class={["absolute h-3 transition-all duration-300", if((s.delta || 0) >= 0, do: "bg-success/70 left-1/2", else: "bg-error/70 right-1/2")]}
                  style={"width: #{min(abs(s.delta || 0) / @max_abs_delta * 50, 50)}%"}
                />
              </div>
            </div>
            <div class={["text-xs font-mono font-semibold w-16 shrink-0 text-right", if((s.delta || 0) >= 0, do: "text-success", else: "text-error")]}>
              {if (s.delta || 0) >= 0, do: "+", else: ""}{format_sat_delta(s.delta)}pts
            </div>
          </div>
        </div>
        <div :if={@no_data > 0} class="mt-3 border border-base-200 overflow-hidden">
          <div class="px-3 py-2 bg-base-200/50 border-b border-base-200">
            <p class="text-[10px] text-base-content/40 uppercase tracking-wide font-medium">
              {@no_data} school{if @no_data != 1, do: "s", else: ""} excluded — no SAT comparison available
            </p>
          </div>
          <table class="w-full">
            <tbody>
              <tr :for={s <- Enum.filter(@stats, & &1.no_lea_found)} class="border-b border-base-200 last:border-0">
                <td class="px-3 py-1.5 text-xs text-base-content/40">{s.school_name}</td>
                <td class="px-3 py-1.5 text-xs font-mono text-base-content/30">{s.building_code}</td>
                <td class="px-3 py-1.5 text-xs text-base-content/30 italic text-right">{s.exclusion_reason}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Data loading
  # ---------------------------------------------------------------------------

  defp load_emo_list do
    MdeEmoContact
    |> Ash.Query.select([:management_organization])
    |> Ash.read!(authorize?: false)
    |> Enum.group_by(& &1.management_organization)
    |> Enum.reject(fn {name, _} -> is_nil(name) end)
    |> Enum.map(fn {name, rows} -> %{name: name, school_count: length(rows)} end)
    |> Enum.sort_by(& &1.name)
  rescue
    _ -> []
  end

  defp load_schools_for_emo(emo_name) do
    contacts =
      MdeEmoContact
      |> Ash.Query.filter(management_organization == ^emo_name)
      |> Ash.read!(authorize?: false)

    district_codes = Enum.map(contacts, & &1.district_code) |> Enum.reject(&is_nil/1)

    contact_map =
      Map.new(contacts, fn c ->
        {c.district_code,
         %{contact_name: c.contact_name, contact_email: c.contact_email, contact_phone: c.contact_phone}}
      end)

    schools =
      if district_codes == [] do
        []
      else
        MdeEntityMaster
        |> Ash.Query.filter(district_code in ^district_codes and entity_status == "Open-Active")
        |> Ash.Query.select([
          :entity_code,
          :entity_official_name,
          :district_code,
          :entity_county_name,
          :entity_actual_grades,
          :entity_authorized_grades
        ])
        |> Ash.Query.sort(entity_official_name: :asc)
        |> Ash.read!(authorize?: false)
      end

    {schools, contact_map}
  rescue
    _ -> {[], %{}}
  end

  defp load_portfolio_stats([], _year), do: []

  defp load_portfolio_stats(building_codes, year) do
    from(s in "mde_school_vs_lea_snapshots",
      where: s.building_code in ^building_codes and s.school_year == ^year,
      select: %{
        building_code: s.building_code,
        school_name: s.school_name,
        no_lea_found: s.no_lea_found,
        school_pct: fragment("(?->>'school_pct')::float", s.all_subjects_avg),
        lea_pct: fragment("(?->>'lea_pct')::float", s.all_subjects_avg),
        delta: fragment("(?->>'delta')::float", s.all_subjects_avg)
      }
    )
    |> Repo.all()
    |> Enum.sort_by(fn s -> if s.no_lea_found, do: -9999, else: s.delta || -9999 end, :desc)
  rescue
    _ -> []
  end

  defp load_sat_portfolio_stats([], _year), do: []

  defp load_sat_portfolio_stats(building_codes, year) do
    snapshot_map =
      from(s in "mde_school_vs_lea_snapshots",
        where: s.building_code in ^building_codes and s.school_year == ^year,
        select: {s.building_code, s.lea_district_code, s.no_lea_found}
      )
      |> Repo.all()
      |> Map.new(fn {bc, ldc, nlf} -> {bc, %{lea_district_code: ldc, no_lea_found: nlf}} end)

    fallback_codes =
      Enum.filter(building_codes, fn bc ->
        case Map.get(snapshot_map, bc) do
          nil -> true
          %{no_lea_found: true} -> true
          _ -> false
        end
      end)

    entity_lea_map =
      if fallback_codes == [] do
        %{}
      else
        from(e in "mde_entity_masters",
          where:
            e.entity_code in ^fallback_codes and
              not is_nil(e.entity_geographic_lea_district_code) and
              e.entity_geographic_lea_district_code != "",
          select: {e.entity_code, e.entity_geographic_lea_district_code}
        )
        |> Repo.all()
        |> Map.new()
      end

    lea_map =
      Map.new(building_codes, fn bc ->
        case Map.get(snapshot_map, bc) do
          %{no_lea_found: false} = entry -> {bc, entry}
          _ ->
            case Map.get(entity_lea_map, bc) do
              nil -> {bc, %{lea_district_code: nil, no_lea_found: true}}
              ldc -> {bc, %{lea_district_code: ldc, no_lea_found: false}}
            end
        end
      end)

    school_sat =
      from(r in "mde_sat_results",
        where:
          r.building_code in ^building_codes and r.school_year == ^year and
            r.rollup_level == "building" and r.subgroup == "All Students",
        select: %{
          building_code: r.building_code,
          building_name: r.building_name,
          score: r.all_subject_score_average
        }
      )
      |> Repo.all()
      |> Map.new(&{&1.building_code, &1})

    lea_codes =
      lea_map |> Map.values() |> Enum.map(& &1.lea_district_code) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    lea_sat =
      if lea_codes == [] do
        %{}
      else
        from(r in "mde_sat_results",
          where:
            r.district_code in ^lea_codes and r.school_year == ^year and
              r.rollup_level == "district" and r.subgroup == "All Students",
          select: %{district_code: r.district_code, score: r.all_subject_score_average}
        )
        |> Repo.all()
        |> Map.new(&{&1.district_code, &1.score})
      end

    building_codes
    |> Enum.map(fn bc ->
      lea_info = Map.get(lea_map, bc, %{lea_district_code: nil, no_lea_found: true})
      school_info = Map.get(school_sat, bc)
      school_score = school_info && decimal_to_float(school_info.score)
      school_name = (school_info && school_info.building_name) || bc

      lea_score =
        if lea_info.no_lea_found or is_nil(lea_info.lea_district_code) do
          nil
        else
          raw = Map.get(lea_sat, lea_info.lea_district_code)
          raw && decimal_to_float(raw)
        end

      delta = if school_score && lea_score, do: school_score - lea_score, else: nil

      {no_lea, exclusion_reason} =
        cond do
          is_nil(school_score) -> {true, "No school SAT data"}
          lea_info.no_lea_found and is_nil(Map.get(entity_lea_map, bc)) -> {true, "No geographic LEA assigned"}
          is_nil(lea_score) -> {true, "LEA has no SAT data (#{lea_info.lea_district_code})"}
          true -> {false, nil}
        end

      %{
        building_code: bc,
        school_name: school_name,
        school_score: school_score,
        lea_score: lea_score,
        delta: delta,
        no_lea_found: no_lea,
        exclusion_reason: exclusion_reason
      }
    end)
    |> Enum.reject(fn s -> is_nil(s.school_score) end)
    |> Enum.sort_by(fn s -> if s.no_lea_found, do: -99_999, else: s.delta || -99_999 end, :desc)
  rescue
    _ -> []
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp filter_emos(emos, ""), do: emos

  defp filter_emos(emos, search) do
    search_lower = String.downcase(search)
    Enum.filter(emos, fn emo -> String.contains?(String.downcase(emo.name || ""), search_lower) end)
  end

  defp filter_schools(schools, ""), do: schools

  defp filter_schools(schools, search) do
    search_lower = String.downcase(search)

    Enum.filter(schools, fn school ->
      name = school.entity_official_name || ""
      code = school.district_code || ""
      county = school.entity_county_name || ""

      String.contains?(String.downcase(name), search_lower) or
        String.contains?(String.downcase(code), search_lower) or
        String.contains?(String.downcase(county), search_lower)
    end)
  end

  defp decimal_to_float(nil), do: nil
  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp decimal_to_float(f) when is_float(f), do: f
  defp decimal_to_float(i) when is_integer(i), do: i * 1.0

  defp format_delta(nil), do: "0.0"
  defp format_delta(d), do: :erlang.float_to_binary(d * 1.0, decimals: 1)

  defp format_sat_delta(nil), do: "0"
  defp format_sat_delta(d), do: :erlang.float_to_binary(d * 1.0, decimals: 1)

  defp short_name(nil), do: "—"

  defp short_name(name) do
    name
    |> String.replace(~r/\b(Academy|Charter|School|Public|Michigan|PSA)\b/i, "")
    |> String.replace(~r/\s{2,}/, " ")
    |> String.trim()
    |> then(fn s -> if String.length(s) > 22, do: String.slice(s, 0, 21) <> "…", else: s end)
  end
end
