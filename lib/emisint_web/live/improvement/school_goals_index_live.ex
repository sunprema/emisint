defmodule EmisintWeb.Improvement.SchoolGoalsIndexLive do
  @moduledoc """
  ND First landing page: the pilot schools (`Emisint.Improvement.Pilot`) with
  goal plans that the signed-in user can read in their organization. Users
  without a school membership see an empty state.
  """
  use EmisintWeb, :live_view

  import EmisintWeb.Improvement.Components, only: [school_tabs: 1]

  alias Emisint.Improvement.{Dashboard, Pilot}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "ND First",
       tabs: Pilot.roster(),
       schools:
         Dashboard.list_schools(socket.assigns.scope, institution_ids: Pilot.institution_ids())
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="p-4 md:p-6 max-w-4xl mx-auto space-y-6">
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

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.link
            :for={school <- @schools}
            navigate={~p"/school-goals/#{school.slug}"}
            class="bg-base-100 border border-base-200 rounded-xl p-4 hover:border-primary transition-colors"
            id={"school-#{school.slug}"}
          >
            <div class="font-semibold">{school.name}</div>
            <div class="text-sm text-base-content/60">{school.district_name}</div>
            <div class="text-xs text-base-content/50 mt-1 font-mono">
              {school.state} {school.state_entity_id}<span :if={school.grade_span}> · Grades {school.grade_span}</span>
            </div>
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
