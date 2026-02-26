defmodule EmisintWeb.Dashboard.PortfolioLive do
  use EmisintWeb, :live_view

  require Ash.Query

  on_mount {EmisintWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    oid = user.organization_id

    schools = Ash.read!(Emisint.Accounts.School, tenant: oid, actor: user)

    evals_with_goals =
      Emisint.Compliance.GoalEvaluation
      |> Ash.Query.load(:schedule71_goal)
      |> Ash.read!(tenant: oid, actor: user)

    evals_by_school =
      Enum.group_by(evals_with_goals, fn e ->
        if e.schedule71_goal, do: e.schedule71_goal.school_id, else: nil
      end)

    triggers =
      Emisint.Analytics.InterventionTrigger
      |> Ash.Query.filter(status == :active)
      |> Ash.read!(tenant: oid, actor: user)

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
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <div>
          <h1 class="text-2xl font-bold">Portfolio Overview</h1>
          <p class="text-base-content/60 text-sm mt-1">
            Schedule 7-1 compliance and performance across all academies
          </p>
        </div>

        <%!-- Stats bar --%>
        <div class="stats stats-horizontal shadow w-full overflow-x-auto">
          <div class="stat">
            <div class="stat-figure text-primary">
              <.icon name="hero-building-office" class="size-8" />
            </div>
            <div class="stat-title">Schools</div>
            <div class="stat-value text-primary">{length(@schools)}</div>
          </div>
          <div class="stat">
            <div class="stat-figure text-success">
              <.icon name="hero-check-badge" class="size-8" />
            </div>
            <div class="stat-title">On Track</div>
            <div class="stat-value text-success">{@goal_counts.on_track}</div>
          </div>
          <div class="stat">
            <div class="stat-figure text-warning">
              <.icon name="hero-exclamation-triangle" class="size-8" />
            </div>
            <div class="stat-title">Approaching</div>
            <div class="stat-value text-warning">{@goal_counts.approaching}</div>
          </div>
          <div class="stat">
            <div class="stat-figure text-error">
              <.icon name="hero-x-circle" class="size-8" />
            </div>
            <div class="stat-title">Below Target</div>
            <div class="stat-value text-error">{@goal_counts.below}</div>
          </div>
        </div>

        <%!-- Empty state --%>
        <div :if={@schools == []} class="card bg-base-200 shadow-sm">
          <div class="card-body items-center text-center py-12">
            <.icon name="hero-building-office" class="size-12 text-base-content/30" />
            <p class="text-base-content/60 mt-2">No schools found. Add a school to get started.</p>
          </div>
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
    <div class="card bg-base-100 shadow-sm border border-base-200 hover:shadow-md transition-shadow">
      <div class="card-body p-5">
        <div class="flex items-start justify-between gap-2">
          <div class="min-w-0 flex-1">
            <h2 class="card-title text-base truncate">{@school.name}</h2>
            <p class="text-sm text-base-content/60">{@school.city || @school.county}</p>
          </div>
          <div :if={@trigger_count > 0} class="badge badge-error badge-sm gap-1 shrink-0">
            <.icon name="hero-bell-alert" class="size-3" />
            {@trigger_count}
          </div>
        </div>

        <%!-- Traffic light badges --%>
        <div :if={@total_goals > 0} class="flex flex-wrap gap-1 mt-3">
          <span :if={@exceeds > 0} class="badge badge-success gap-1">
            <.icon name="hero-check-circle" class="size-3" /> {@exceeds} Exceeds
          </span>
          <span :if={@meets > 0} class="badge badge-success badge-outline gap-1">
            <.icon name="hero-check" class="size-3" /> {@meets} Meets
          </span>
          <span :if={@approaching > 0} class="badge badge-warning gap-1">
            <.icon name="hero-exclamation-triangle" class="size-3" /> {@approaching} Approaching
          </span>
          <span :if={@below > 0} class="badge badge-error gap-1">
            <.icon name="hero-x-circle" class="size-3" /> {@below} Below
          </span>
        </div>

        <div :if={@total_goals == 0} class="mt-3">
          <span class="badge badge-ghost badge-sm">No goals configured</span>
        </div>

        <div class="card-actions justify-between items-center mt-3">
          <div class="text-xs text-base-content/50">
            {@school.mde_building_code}
          </div>
          <.link navigate={~p"/schools/#{@school.id}"} class="btn btn-ghost btn-xs gap-1">
            Details <.icon name="hero-arrow-right" class="size-3" />
          </.link>
        </div>
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
