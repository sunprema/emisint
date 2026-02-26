defmodule EmisintWeb.Compliance.TrackerLive do
  use EmisintWeb, :live_view

  require Ash.Query

  @status_filters [:all, :exceeds, :meets, :approaching, :below, :insufficient_data]

  def mount(%{"school_id" => school_id}, _session, socket) do
    scope = socket.assigns.scope

    school = Emisint.Accounts.get_school!(school_id, scope: scope)
    goals_with_evals = load_goals_with_evals(school_id, scope)

    {:ok,
     socket
     |> assign(:page_title, "#{school.name} — Schedule 7-1")
     |> assign(:school, school)
     |> assign(:goals_with_evals, goals_with_evals)
     |> assign(:filter_status, :all)
     |> assign(:status_filters, @status_filters)}
  end

  def handle_event("filter_status", %{"status" => status}, socket) do
    atom = String.to_existing_atom(status)

    if atom in @status_filters do
      {:noreply, assign(socket, :filter_status, atom)}
    else
      {:noreply, socket}
    end
  end

  def render(assigns) do
    assigns =
      assign(assigns, :filtered, filter_goals(assigns.goals_with_evals, assigns.filter_status))

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <%!-- Header --%>
        <div class="flex items-center gap-3 flex-wrap">
          <.link navigate={~p"/schools/#{@school.id}"} class="btn btn-ghost btn-sm btn-circle">
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <div>
            <h1 class="text-2xl font-bold">Schedule 7-1 Tracker</h1>
            <p class="text-base-content/60 text-sm">{@school.name}</p>
          </div>
        </div>

        <%!-- Summary badges --%>
        <div class="flex flex-wrap gap-2">
          <.status_count_badge
            goals_with_evals={@goals_with_evals}
            status={:exceeds}
            label="Exceeds"
            class="badge-success"
          />
          <.status_count_badge
            goals_with_evals={@goals_with_evals}
            status={:meets}
            label="Meets"
            class="badge-success badge-outline"
          />
          <.status_count_badge
            goals_with_evals={@goals_with_evals}
            status={:approaching}
            label="Approaching"
            class="badge-warning"
          />
          <.status_count_badge
            goals_with_evals={@goals_with_evals}
            status={:below}
            label="Below"
            class="badge-error"
          />
          <.status_count_badge
            goals_with_evals={@goals_with_evals}
            status={:insufficient_data}
            label="Insufficient Data"
            class="badge-ghost"
          />
        </div>

        <%!-- Filter buttons --%>
        <div class="flex flex-wrap gap-2">
          <button
            :for={status <- @status_filters}
            phx-click="filter_status"
            phx-value-status={status}
            class={[
              "btn btn-sm",
              @filter_status == status && "btn-primary",
              @filter_status != status && "btn-ghost"
            ]}
          >
            {filter_label(status)}
          </button>
        </div>

        <%!-- Empty state --%>
        <div :if={@goals_with_evals == []} class="card bg-base-200">
          <div class="card-body items-center py-12 text-center">
            <.icon name="hero-clipboard-document-list" class="size-12 text-base-content/30" />
            <p class="text-base-content/60 mt-2">No Schedule 7-1 goals configured for this school.</p>
          </div>
        </div>

        <div :if={@filtered == [] and @goals_with_evals != []} class="card bg-base-200">
          <div class="card-body items-center py-8 text-center">
            <p class="text-base-content/60">No goals match the selected filter.</p>
          </div>
        </div>

        <%!-- Goals list --%>
        <div class="space-y-3">
          <.goal_card :for={{goal, eval} <- @filtered} goal={goal} eval={eval} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  def status_count_badge(assigns) do
    count =
      Enum.count(assigns.goals_with_evals, fn {_goal, eval} ->
        eval && eval.status == assigns.status
      end)

    assigns = assign(assigns, :count, count)

    ~H"""
    <span :if={@count > 0} class={["badge gap-1", @class]}>
      {@count} {@label}
    </span>
    """
  end

  def goal_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body p-5">
        <div class="flex items-start gap-4 flex-wrap">
          <div class="flex-1 min-w-0">
            <h3 class="font-semibold text-base">{@goal.title}</h3>
            <div class="flex flex-wrap gap-2 mt-2 text-sm text-base-content/60">
              <span class="flex items-center gap-1">
                <.icon name="hero-tag" class="size-3.5" />
                {goal_type_label(@goal.goal_type)}
              </span>
              <span class="flex items-center gap-1">
                <.icon name="hero-academic-cap" class="size-3.5" />
                {String.capitalize(@goal.subject)}
              </span>
              <span :if={@goal.testing_window} class="flex items-center gap-1">
                <.icon name="hero-calendar" class="size-3.5" />
                {String.capitalize(to_string(@goal.testing_window))}
              </span>
              <span :if={@goal.subgroup && @goal.subgroup != :all} class="flex items-center gap-1">
                <.icon name="hero-users" class="size-3.5" />
                {subgroup_label(@goal.subgroup)}
              </span>
            </div>
          </div>

          <div class="shrink-0 text-right">
            <.eval_status_badge eval={@eval} />
            <div :if={@eval} class="mt-2 text-xs text-base-content/50">
              Target: {format_value(@goal.goal_type, @eval.target_value)} ·
              Actual: {format_value(@goal.goal_type, @eval.actual_value)}
            </div>
          </div>
        </div>

        <%!-- Progress bar for numeric goals --%>
        <div :if={@eval && @eval.actual_value && @eval.target_value} class="mt-3">
          <div class="flex justify-between text-xs text-base-content/60 mb-1">
            <span>Progress toward target</span>
            <span>
              {format_value(@goal.goal_type, @eval.actual_value)} / {format_value(
                @goal.goal_type,
                @eval.target_value
              )}
            </span>
          </div>
          <progress
            class={["progress w-full", eval_progress_color(@eval.status)]}
            value={progress_pct(@eval.actual_value, @eval.target_value)}
            max="100"
          >
          </progress>
        </div>

        <div
          :if={@eval && @eval.data_points_count == 0}
          class="mt-2 text-xs text-warning flex items-center gap-1"
        >
          <.icon name="hero-exclamation-triangle" class="size-3" /> No assessment data available yet
        </div>
      </div>
    </div>
    """
  end

  def eval_status_badge(assigns) do
    ~H"""
    <span :if={is_nil(@eval)} class="badge badge-ghost badge-sm">No data</span>
    <span :if={@eval && @eval.status == :exceeds} class="badge badge-success gap-1">
      <.icon name="hero-check-circle" class="size-3" /> Exceeds
    </span>
    <span :if={@eval && @eval.status == :meets} class="badge badge-success badge-outline gap-1">
      <.icon name="hero-check" class="size-3" /> Meets
    </span>
    <span :if={@eval && @eval.status == :approaching} class="badge badge-warning gap-1">
      <.icon name="hero-exclamation-triangle" class="size-3" /> Approaching
    </span>
    <span :if={@eval && @eval.status == :below} class="badge badge-error gap-1">
      <.icon name="hero-x-circle" class="size-3" /> Below
    </span>
    <span :if={@eval && @eval.status == :insufficient_data} class="badge badge-ghost badge-sm">
      Insufficient Data
    </span>
    """
  end

  # --- Helpers ---

  defp load_goals_with_evals(school_id, scope) do
    goals =
      Emisint.Compliance.Schedule71Goal
      |> Ash.Query.filter(school_id == ^school_id)
      |> Ash.read!(scope: scope)

    evaluations =
      Emisint.Compliance.GoalEvaluation
      |> Ash.read!(scope: scope)

    eval_by_goal = Map.new(evaluations, fn e -> {e.schedule71_goal_id, e} end)

    Enum.map(goals, fn goal -> {goal, Map.get(eval_by_goal, goal.id)} end)
  end

  defp filter_goals(goals_with_evals, :all), do: goals_with_evals

  defp filter_goals(goals_with_evals, status) do
    Enum.filter(goals_with_evals, fn {_goal, eval} ->
      eval && eval.status == status
    end)
  end

  defp filter_label(:all), do: "All"
  defp filter_label(:exceeds), do: "Exceeds"
  defp filter_label(:meets), do: "Meets"
  defp filter_label(:approaching), do: "Approaching"
  defp filter_label(:below), do: "Below"
  defp filter_label(:insufficient_data), do: "No Data"

  defp goal_type_label(:proficiency_threshold), do: "Proficiency"
  defp goal_type_label(:sgp_median), do: "SGP Median"
  defp goal_type_label(:outperform_district), do: "Outperform District"
  defp goal_type_label(:growth_target), do: "Growth Target"

  defp subgroup_label(:economically_disadvantaged), do: "Econ. Disadvantaged"
  defp subgroup_label(:english_learner), do: "English Learner"
  defp subgroup_label(:special_education), do: "Special Education"
  defp subgroup_label(other), do: to_string(other)

  defp format_value(:proficiency_threshold, nil), do: "—"
  defp format_value(:outperform_district, nil), do: "—"

  defp format_value(type, d) when type in [:proficiency_threshold, :outperform_district] do
    pct = Decimal.mult(d, 100) |> Decimal.round(1) |> Decimal.to_string()
    "#{pct}%"
  end

  defp format_value(_, nil), do: "—"
  defp format_value(_, d), do: Decimal.round(d, 1) |> Decimal.to_string()

  defp progress_pct(actual, target) do
    if Decimal.compare(target, Decimal.new(0)) == :eq do
      0
    else
      ratio = Decimal.div(actual, target) |> Decimal.round(2)
      min(Decimal.mult(ratio, 100) |> Decimal.to_integer(), 100)
    end
  end

  defp eval_progress_color(:exceeds), do: "progress-success"
  defp eval_progress_color(:meets), do: "progress-success"
  defp eval_progress_color(:approaching), do: "progress-warning"
  defp eval_progress_color(:below), do: "progress-error"
  defp eval_progress_color(_), do: "progress-primary"
end
