defmodule EmisintWeb.Improvement.SchoolGoalsIndexLive do
  @moduledoc """
  ND First landing page: the portfolio summary (`Emisint.Improvement.Portfolio`,
  the workbook's "Goals Dashboard" and "Performance-Based Payment" sheets),
  then the pilot schools (`Emisint.Improvement.Pilot`) with goal plans that
  the signed-in user can read in their organization. Users without a school
  membership see an empty state.
  """
  use EmisintWeb, :live_view

  import EmisintWeb.Improvement.Components, only: [school_tabs: 1]
  import EmisintWeb.Improvement.PortfolioComponents, only: [portfolio: 1]

  alias Emisint.Improvement.{Dashboard, Pilot, Portfolio}

  @impl true
  def mount(_params, _session, socket) do
    schools =
      Dashboard.list_schools(socket.assigns.scope, institution_ids: Pilot.institution_ids())

    readable = MapSet.new(schools, & &1.slug)
    tabs = Pilot.tabs(readable)

    {:ok,
     assign(socket,
       page_title: "ND First",
       tabs: tabs,
       schools: schools,
       groups: groups(tabs, schools, readable),
       summary: Portfolio.summary(socket.assigns.scope)
     )}
  end

  # One card per participant, in tab order: its main record (when readable)
  # and, for a district participant, its readable buildings.
  defp groups(tabs, schools, readable) do
    by_slug = Map.new(schools, &{&1.slug, &1})

    for %{enabled?: true} = tab <- tabs do
      nav =
        Pilot.participant_nav(%{slug: tab.slug, state_entity_id: tab.institution_id}, readable)

      buildings =
        if nav,
          do: for(item <- nav.items, item.slug != tab.slug, do: by_slug[item.slug]),
          else: []

      %{
        name: tab.name,
        slug: tab.slug,
        main: by_slug[tab.slug],
        buildings: buildings,
        provisional?: nav != nil and nav.provisional?
      }
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="p-4 md:p-6 max-w-6xl mx-auto space-y-6">
        <.school_tabs tabs={@tabs} />
        <div class="flex flex-col md:flex-row md:items-start md:justify-between gap-3">
          <div>
            <h1 class="text-2xl font-bold">ND First</h1>
            <div class="text-sm text-base-content/70 mt-2 space-y-2 max-w-2xl" id="nd-first-intro">
              <p>
                ND First schools are listed on the North Dakota Department of Public Instruction's <a
                  href="https://www.nd.gov/dpi/districtsschools/essa/accountability-support-improvement/nd-first"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="link link-primary"
                >
                  accountability, support and improvement pages
                </a>.
              </p>
              <p>
                For each school, this page tracks its MOU goals and their seasonal 0–3 implementation
                ratings, its 18- and 36-month targets, its annual Proficient-or-Advanced targets from
                its continuous improvement plan, and the state's published results from ND Insights.
              </p>
            </div>
          </div>
        </div>

        <div
          :if={@schools == []}
          class="bg-base-100 border border-base-200 rounded-xl text-center py-12 text-base-content/50"
          id="no-schools"
        >
          No schools are available to you. Ask your organization admin for access.
        </div>

        <.portfolio :if={@summary.rows != []} summary={@summary} />

        <h2 :if={@groups != []} class="text-lg font-semibold" id="participants-heading">
          Participants and schools
        </h2>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div
            :for={g <- @groups}
            class="bg-base-100 border border-base-200 rounded-xl p-4 space-y-2"
            id={"participant-#{g.slug}"}
          >
            <.link
              :if={g.main}
              navigate={~p"/school-goals/#{g.main.slug}"}
              class="block hover:text-primary transition-colors"
              id={"school-#{g.main.slug}"}
            >
              <div class="font-semibold">{g.main.name}</div>
              <div class="text-sm text-base-content/60">{g.main.district_name}</div>
              <div class="text-xs text-base-content/50 mt-1 font-mono">
                {g.main.state} {g.main.state_entity_id}<span :if={g.main.grade_span}> · Grades {g.main.grade_span}</span>
              </div>
            </.link>
            <div :if={!g.main} class="font-semibold">{g.name}</div>
            <span
              :if={g.provisional?}
              class="badge badge-warning badge-soft badge-sm"
              id={"participant-#{g.slug}-provisional"}
            >
              Workbook scope provisional
            </span>
            <ul :if={g.buildings != []} class="text-sm space-y-1 border-t border-base-200 pt-2">
              <li :for={b <- g.buildings}>
                <.link
                  navigate={~p"/school-goals/#{b.slug}"}
                  class="link link-hover"
                  id={"school-#{b.slug}"}
                >
                  {b.name}
                </.link>
                <span class="text-xs text-base-content/50 font-mono">{b.state_entity_id}</span>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
