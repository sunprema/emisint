defmodule EmisintWeb.Improvement.MetricHistoryLive do
  @moduledoc """
  Full history of one metric: every actual result and implementation rating,
  per period, including superseded entries and their corrections. Nothing is
  ever removed; a correction is a new entry that points at the one it replaces.
  """
  use EmisintWeb, :live_view

  import EmisintWeb.Improvement.Components

  alias Emisint.Improvement.{Access, Dashboard}

  @impl true
  def mount(%{"slug" => slug, "code" => code}, _session, socket) do
    scope = socket.assigns.scope

    with {:ok, school} <- Dashboard.fetch_school(scope, slug),
         {:ok, defs} <- Dashboard.load_plan(scope, school),
         {:ok, history} <- Dashboard.load_history(scope, defs.plan, code) do
      {:ok,
       assign(socket,
         page_title: "#{history.metric.code} history · #{school.name}",
         school: school,
         periods: defs.periods,
         history: history,
         can_contribute?: Access.can_contribute?(scope.current_user, scope.current_tenant, school)
       )}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "That metric was not found, or you don't have access to it.")
         |> push_navigate(to: ~p"/school-goals")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="p-4 md:p-6 max-w-5xl mx-auto space-y-6">
        <div>
          <.link
            navigate={~p"/school-goals/#{@school.slug}"}
            class="text-sm text-base-content/50 hover:text-base-content flex items-center gap-1 mb-3"
          >
            <.icon name="hero-arrow-left" class="size-4" /> {@school.name}
          </.link>
          <div class="font-mono text-xs text-base-content/50">
            Goal {@history.goal.number} · {@history.metric.code}
          </div>
          <h1 class="text-2xl font-bold">{@history.metric.description}</h1>
          <div class="flex flex-wrap gap-4 mt-2 text-sm">
            <span>Baseline: <.target metric={@history.metric} field={:baseline_value} /></span>
            <span>18-month target: <.target metric={@history.metric} field={:target_18m} /></span>
            <span>36-month target: <.target metric={@history.metric} field={:target_36m} /></span>
          </div>
          <.target_source_details metric={@history.metric} class="mt-2 max-w-xl" />
        </div>

        <.history_section
          id="actual-history"
          title="Actual results"
          entries={@history.actuals}
          periods={@periods}
          users={@history.users}
          school={@school}
          metric={@history.metric}
          can_contribute?={@can_contribute?}
          kind={:actual}
        />

        <.history_section
          id="rating-history"
          title="Implementation ratings (0–3)"
          entries={@history.ratings}
          periods={@periods}
          users={@history.users}
          school={@school}
          metric={@history.metric}
          can_contribute?={@can_contribute?}
          kind={:rating}
        />
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :entries, :list, required: true
  attr :periods, :list, required: true
  attr :users, :map, required: true
  attr :school, :map, required: true
  attr :metric, :map, required: true
  attr :can_contribute?, :boolean, required: true
  attr :kind, :atom, required: true

  defp history_section(assigns) do
    assigns = assign(assigns, :groups, group_by_period(assigns.entries, assigns.periods))

    ~H"""
    <section class="bg-base-100 border border-base-200 rounded-xl overflow-hidden" id={@id}>
      <div class="px-4 py-3 border-b border-base-200 flex items-center gap-2">
        <h2 class="font-semibold">{@title}</h2>
        <span class="badge badge-ghost badge-sm">{length(@entries)} entries</span>
      </div>

      <div :if={@entries == []} class="text-center py-8 text-base-content/40">
        Nothing has been reported yet.
      </div>

      <div :for={{period, entries} <- @groups} class="border-b border-base-200 last:border-b-0">
        <div class="px-4 py-2 bg-base-200/40 text-sm font-medium">{period.label}</div>
        <ol class="divide-y divide-base-200">
          <li
            :for={entry <- entries}
            class="px-4 py-3 flex items-start justify-between gap-4"
            id={"entry-#{entry.id}"}
          >
            <div class="space-y-1">
              <div class="flex flex-wrap items-center gap-2">
                <span :if={@kind == :actual}><.actual_value entry={entry} metric={@metric} /></span>
                <span :if={@kind == :rating}><.rating_value entry={entry} /></span>
                <span :if={entry.current?} class="badge badge-success badge-xs">Current</span>
                <span :if={!entry.current?} class="badge badge-ghost badge-xs">Superseded</span>
                <span :if={entry.kind == :observation} class="badge badge-outline badge-xs">
                  Original
                </span>
              </div>
              <.provenance entry={entry} users={@users} />
              <div :if={entry.corrects_id} class="text-xs text-base-content/50">
                Corrects the entry recorded {corrected_at(entries, entry.corrects_id)}
              </div>
            </div>
            <.link
              :if={entry.current? and @can_contribute?}
              navigate={
                ~p"/school-goals/#{@school.slug}?#{[period: period.code, update: @metric.code]}"
              }
              class="btn btn-xs btn-ghost whitespace-nowrap"
            >
              Correct this
            </.link>
          </li>
        </ol>
      </div>
    </section>
    """
  end

  defp group_by_period(entries, periods) do
    by_period = Enum.group_by(entries, & &1.reporting_period_id)

    for period <- Enum.reverse(periods), list = by_period[period.id], list != nil do
      {period, Enum.sort_by(list, & &1.recorded_at, {:desc, DateTime})}
    end
  end

  defp corrected_at(entries, id) do
    case Enum.find(entries, &(&1.id == id)) do
      nil -> "earlier"
      entry -> format_datetime(entry.recorded_at)
    end
  end
end
