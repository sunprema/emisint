defmodule EmisintWeb.Dashboard.PortfolioLive do
  use EmisintWeb, :live_view

  require Ash.Query

  on_mount {EmisintWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    scope = socket.assigns.scope

    schools = Ash.read!(Emisint.Accounts.School, scope: scope)

    evals_with_goals =
      Emisint.Compliance.GoalEvaluation
      |> Ash.Query.load(:schedule71_goal)
      |> Ash.read!(scope: scope)

    evals_by_school =
      Enum.group_by(evals_with_goals, fn e ->
        if e.schedule71_goal, do: e.schedule71_goal.school_id, else: nil
      end)

    triggers =
      Emisint.Analytics.InterventionTrigger
      |> Ash.Query.filter(status == :active)
      |> Ash.read!(scope: scope)

    trigger_count_by_school = Enum.frequencies_by(triggers, & &1.school_id)
    goal_counts = tally_statuses(evals_with_goals)

    {:ok,
     socket
     |> assign(:page_title, "Portfolio Overview")
     |> assign(:schools, schools)
     |> assign(:evals_by_school, evals_by_school)
     |> assign(:trigger_count_by_school, trigger_count_by_school)
     |> assign(:goal_counts, goal_counts)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-6xl mx-auto space-y-8">
        <%!-- Header --%>
        <div class="flex items-center gap-4">
          <div class="p-2.5 bg-primary/10 border border-primary/20">
            <.icon name="hero-squares-2x2" class="size-6 text-primary" />
          </div>
          <div>
            <h1 class="text-2xl font-bold tracking-tight">Portfolio Overview</h1>
            <p class="text-sm text-base-content/50 mt-0.5">
              Schedule 7-1 compliance and performance across all academies
            </p>
          </div>
        </div>

        <%!-- Stats row --%>
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <div class="bg-base-100 border border-base-200 p-5">
            <div class="flex items-center justify-between mb-3">
              <span class="text-xs font-medium text-base-content/40 uppercase tracking-wider">
                Schools
              </span>
              <div class="p-1.5 bg-primary/10">
                <.icon name="hero-building-office" class="size-4 text-primary" />
              </div>
            </div>
            <div class="text-3xl font-bold tracking-tight">{length(@schools)}</div>
          </div>

          <div class="bg-base-100 border border-base-200 p-5">
            <div class="flex items-center justify-between mb-3">
              <span class="text-xs font-medium text-base-content/40 uppercase tracking-wider">
                On Track
              </span>
              <div class="p-1.5 bg-success/10">
                <.icon name="hero-check-badge" class="size-4 text-success" />
              </div>
            </div>
            <div class="text-3xl font-bold tracking-tight text-success">
              {@goal_counts.on_track}
            </div>
          </div>

          <div class="bg-base-100 border border-base-200 p-5">
            <div class="flex items-center justify-between mb-3">
              <span class="text-xs font-medium text-base-content/40 uppercase tracking-wider">
                Approaching
              </span>
              <div class="p-1.5 bg-warning/10">
                <.icon name="hero-exclamation-triangle" class="size-4 text-warning" />
              </div>
            </div>
            <div class="text-3xl font-bold tracking-tight text-warning">
              {@goal_counts.approaching}
            </div>
          </div>

          <div class="bg-base-100 border border-base-200 p-5">
            <div class="flex items-center justify-between mb-3">
              <span class="text-xs font-medium text-base-content/40 uppercase tracking-wider">
                Below Target
              </span>
              <div class="p-1.5 bg-error/10">
                <.icon name="hero-x-circle" class="size-4 text-error" />
              </div>
            </div>
            <div class="text-3xl font-bold tracking-tight text-error">{@goal_counts.below}</div>
          </div>
        </div>

        <%!-- Empty state --%>
        <div
          :if={@schools == []}
          class="bg-base-100 border border-base-200 flex flex-col items-center justify-center py-16 text-center"
        >
          <div class="p-3 bg-base-200 mb-3">
            <.icon name="hero-building-office" class="size-7 text-base-content/25" />
          </div>
          <p class="text-sm font-medium text-base-content/40">No schools found</p>
          <p class="text-xs text-base-content/30 mt-1">Add a school to get started.</p>
        </div>

        <%!-- Schools grid --%>
        <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          <.school_card
            :for={school <- @schools}
            school={school}
            evaluations={Map.get(@evals_by_school, school.id, [])}
            trigger_count={Map.get(@trigger_count_by_school, school.id, 0)}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  def school_card(assigns) do
    counts = Enum.frequencies_by(assigns.evaluations, & &1.status)

    assigns =
      assigns
      |> assign(:exceeds, Map.get(counts, :exceeds, 0))
      |> assign(:meets, Map.get(counts, :meets, 0))
      |> assign(:approaching, Map.get(counts, :approaching, 0))
      |> assign(:below, Map.get(counts, :below, 0))
      |> assign(:total_goals, length(assigns.evaluations))

    ~H"""
    <div class="bg-base-100 border border-base-200 hover:transition-all hover:-translate-y-0.5 overflow-hidden">
      <div class="p-5">
        <div class="flex items-start justify-between gap-2 mb-4">
          <div class="min-w-0 flex-1">
            <h2 class="font-semibold text-base truncate">{@school.name}</h2>
            <p class="text-sm text-base-content/50 mt-0.5">{@school.city || @school.county}</p>
          </div>
          <div
            :if={@trigger_count > 0}
            class="flex items-center gap-1 px-2 py-1 bg-error/10 text-error text-xs font-medium shrink-0"
          >
            <.icon name="hero-bell-alert" class="size-3" /> {@trigger_count}
          </div>
        </div>

        <%!-- Traffic light mini-bar --%>
        <div :if={@total_goals > 0} class="space-y-2">
          <div class="flex gap-1 h-1.5 rounded-full overflow-hidden">
            <div
              :if={@exceeds > 0}
              class="bg-success rounded-full transition-all"
              style={"width: #{@exceeds / @total_goals * 100}%"}
            >
            </div>
            <div
              :if={@meets > 0}
              class="bg-success/40 rounded-full transition-all"
              style={"width: #{@meets / @total_goals * 100}%"}
            >
            </div>
            <div
              :if={@approaching > 0}
              class="bg-warning rounded-full transition-all"
              style={"width: #{@approaching / @total_goals * 100}%"}
            >
            </div>
            <div
              :if={@below > 0}
              class="bg-error rounded-full transition-all"
              style={"width: #{@below / @total_goals * 100}%"}
            >
            </div>
          </div>
          <div class="flex flex-wrap gap-x-3 gap-y-1 text-xs text-base-content/50">
            <span :if={@exceeds > 0} class="flex items-center gap-1">
              <span class="inline-block size-1.5 rounded-full bg-success"></span>
              {@exceeds} Exceeds
            </span>
            <span :if={@meets > 0} class="flex items-center gap-1">
              <span class="inline-block size-1.5 rounded-full bg-success/50"></span>
              {@meets} Meets
            </span>
            <span :if={@approaching > 0} class="flex items-center gap-1">
              <span class="inline-block size-1.5 rounded-full bg-warning"></span>
              {@approaching} Approaching
            </span>
            <span :if={@below > 0} class="flex items-center gap-1">
              <span class="inline-block size-1.5 rounded-full bg-error"></span>
              {@below} Below
            </span>
          </div>
        </div>

        <div :if={@total_goals == 0} class="text-xs text-base-content/30 italic">
          No goals configured
        </div>
      </div>

      <div class="px-5 py-3 border-t border-base-200 flex items-center justify-between bg-base-50/50">
        <span class="text-xs text-base-content/35 font-mono">{@school.mde_building_code}</span>
        <.link
          navigate={~p"/schools/#{@school.id}"}
          class="flex items-center gap-1 text-xs font-medium text-primary hover:text-primary/80 transition-colors"
        >
          View details <.icon name="hero-arrow-right" class="size-3" />
        </.link>
      </div>
    </div>
    """
  end

  defp tally_statuses(evaluations) do
    Enum.reduce(
      evaluations,
      %{on_track: 0, approaching: 0, below: 0, insufficient: 0},
      fn eval, acc ->
        case eval.status do
          :exceeds -> %{acc | on_track: acc.on_track + 1}
          :meets -> %{acc | on_track: acc.on_track + 1}
          :approaching -> %{acc | approaching: acc.approaching + 1}
          :below -> %{acc | below: acc.below + 1}
          _ -> %{acc | insufficient: acc.insufficient + 1}
        end
      end
    )
  end
end
