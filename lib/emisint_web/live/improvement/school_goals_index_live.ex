defmodule EmisintWeb.Improvement.SchoolGoalsIndexLive do
  @moduledoc """
  Lists the schools with goal plans that the signed-in user can read in their
  organization. Users without a school membership see an empty state.
  """
  use EmisintWeb, :live_view

  alias Emisint.Improvement.Dashboard

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "School Goals",
       schools: Dashboard.list_schools(socket.assigns.scope)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="p-4 md:p-6 max-w-4xl mx-auto space-y-6">
        <div>
          <h1 class="text-2xl font-bold">School Goals</h1>
          <p class="text-sm text-base-content/60 mt-1">
            ND First school improvement goals, seasonal progress and annual assessment targets.
          </p>
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
