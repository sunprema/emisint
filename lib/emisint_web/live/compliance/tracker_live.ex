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
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-4xl mx-auto space-y-8">
        <%!-- Header --%>
        <div class="flex items-center gap-3">
          <.link
            navigate={~p"/schools/#{@school.id}"}
            class="p-2 rounded-xl hover:bg-base-200 transition-colors text-base-content/60 hover:text-base-content"
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <div class="flex items-center gap-4">
            <div class="p-2.5 rounded-2xl bg-primary/10 border border-primary/20">
              <.icon name="hero-clipboard-document-check" class="size-6 text-primary" />
            </div>
            <div>
              <h1 class="text-2xl font-bold tracking-tight">Schedule 7-1 Tracker</h1>
              <p class="text-sm text-base-content/50 mt-0.5">{@school.name}</p>
            </div>
          </div>
        </div>

        <%!-- Summary stat chips --%>
        <div class="grid grid-cols-2 sm:grid-cols-5 gap-3">
          <.status_count_chip
            goals_with_evals={@goals_with_evals}
            status={:exceeds}
            label="Exceeds"
            color="text-success"
            bg="bg-success/10"
          />
          <.status_count_chip
            goals_with_evals={@goals_with_evals}
            status={:meets}
            label="Meets"
            color="text-success"
            bg="bg-success/5"
          />
          <.status_count_chip
            goals_with_evals={@goals_with_evals}
            status={:approaching}
            label="Approaching"
            color="text-warning"
            bg="bg-warning/10"
          />
          <.status_count_chip
            goals_with_evals={@goals_with_evals}
            status={:below}
            label="Below"
            color="text-error"
            bg="bg-error/10"
          />
          <.status_count_chip
            goals_with_evals={@goals_with_evals}
            status={:insufficient_data}
            label="No Data"
            color="text-base-content/40"
            bg="bg-base-200"
          />
        </div>

        <%!-- Filter pills --%>
        <div class="flex flex-wrap gap-2">
          <button
            :for={status <- @status_filters}
            phx-click="filter_status"
            phx-value-status={status}
            class={[
              "px-3.5 py-1.5 rounded-full text-sm font-medium transition-all border",
              @filter_status == status &&
                "bg-primary text-primary-content border-primary shadow-sm",
              @filter_status != status &&
                "bg-base-100 text-base-content/60 border-base-200 hover:border-base-300 hover:text-base-content"
            ]}
          >
            {filter_label(status)}
          </button>
        </div>

        <%!-- Empty state --%>
        <div
          :if={@goals_with_evals == []}
          class="rounded-2xl bg-base-100 border border-base-200 flex flex-col items-center justify-center py-16 text-center"
        >
          <div class="p-3 rounded-2xl bg-base-200 mb-3">
            <.icon name="hero-clipboard-document-list" class="size-7 text-base-content/25" />
          </div>
          <p class="text-sm font-medium text-base-content/40">No goals configured</p>
          <p class="text-xs text-base-content/30 mt-1">
            Add Schedule 7-1 goals for this school to start tracking.
          </p>
        </div>

        <div
          :if={@filtered == [] and @goals_with_evals != []}
          class="rounded-2xl bg-base-100 border border-base-200 flex flex-col items-center justify-center py-12 text-center"
        >
          <p class="text-sm text-base-content/40">No goals match the selected filter.</p>
        </div>

        <%!-- Goals list --%>
        <div class="space-y-3">
          <.goal_card :for={{goal, eval} <- @filtered} goal={goal} eval={eval} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  def status_count_chip(assigns) do
    count =
      Enum.count(assigns.goals_with_evals, fn {_goal, eval} ->
        eval && eval.status == assigns.status
      end)

    assigns = assign(assigns, :count, count)

    ~H"""
    <div class={["rounded-xl p-3 text-center border border-transparent", @bg]}>
      <div class={["text-2xl font-bold", @color]}>{@count}</div>
      <div class="text-xs text-base-content/50 mt-0.5">{@label}</div>
    </div>
    """
  end

  def goal_card(assigns) do
    ~H"""
    <div class="rounded-2xl bg-base-100 border border-base-200 shadow-sm overflow-hidden">
      <div class="p-5">
        <div class="flex items-start gap-4 flex-wrap">
          <div class="flex-1 min-w-0">
            <h3 class="font-semibold text-base">{@goal.title}</h3>
            <div class="flex flex-wrap gap-2 mt-2">
              <span class="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-base-200 text-base-content/60">
                <.icon name="hero-tag" class="size-3" />
                {goal_type_label(@goal.goal_type)}
              </span>
              <span class="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-base-200 text-base-content/60">
                <.icon name="hero-academic-cap" class="size-3" />
                {String.capitalize(@goal.subject)}
              </span>
              <span
                :if={@goal.testing_window}
                class="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-base-200 text-base-content/60"
              >
                <.icon name="hero-calendar" class="size-3" />
                {String.capitalize(to_string(@goal.testing_window))}
              </span>
              <span
                :if={@goal.subgroup && @goal.subgroup != :all}
                class="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-base-200 text-base-content/60"
              >
                <.icon name="hero-users" class="size-3" />
                {subgroup_label(@goal.subgroup)}
              </span>
            </div>
          </div>

          <div class="shrink-0 text-right">
            <.eval_status_pill eval={@eval} />
            <div :if={@eval} class="mt-2 text-xs text-base-content/40">
              Target: {format_value(@goal.goal_type, @eval.target_value)} ·
              Actual: {format_value(@goal.goal_type, @eval.actual_value)}
            </div>
          </div>
        </div>

        <%!-- Custom progress bar --%>
        <div :if={@eval && @eval.actual_value && @eval.target_value} class="mt-4">
          <div class="flex justify-between text-xs text-base-content/40 mb-1.5">
            <span>Progress toward target</span>
            <span>
              {format_value(@goal.goal_type, @eval.actual_value)} / {format_value(
                @goal.goal_type,
                @eval.target_value
              )}
            </span>
          </div>
          <div class="w-full bg-base-200 rounded-full h-1.5">
            <div
              class={[
                "h-1.5 rounded-full transition-all duration-500",
                eval_progress_color(@eval.status)
              ]}
              style={"width: #{progress_pct(@eval.actual_value, @eval.target_value)}%"}
            >
            </div>
          </div>
        </div>

        <div
          :if={@eval && @eval.data_points_count == 0}
          class="mt-3 flex items-center gap-1.5 text-xs text-warning bg-warning/5 rounded-lg px-3 py-2"
        >
          <.icon name="hero-exclamation-triangle" class="size-3.5 shrink-0" />
          No assessment data available yet
        </div>
      </div>
    </div>
    """
  end

  def eval_status_pill(assigns) do
    ~H"""
    <span
      :if={is_nil(@eval)}
      class="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium bg-base-200 text-base-content/40"
    >
      No data
    </span>
    <span
      :if={@eval && @eval.status == :exceeds}
      class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-success/15 text-success"
    >
      <.icon name="hero-check-circle" class="size-3" /> Exceeds
    </span>
    <span
      :if={@eval && @eval.status == :meets}
      class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-success/8 text-success border border-success/20"
    >
      <.icon name="hero-check" class="size-3" /> Meets
    </span>
    <span
      :if={@eval && @eval.status == :approaching}
      class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-warning/15 text-warning"
    >
      <.icon name="hero-exclamation-triangle" class="size-3" /> Approaching
    </span>
    <span
      :if={@eval && @eval.status == :below}
      class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-error/15 text-error"
    >
      <.icon name="hero-x-circle" class="size-3" /> Below
    </span>
    <span
      :if={@eval && @eval.status == :insufficient_data}
      class="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium bg-base-200 text-base-content/40"
    >
      Insufficient Data
    </span>
    """
  end

  # Keep old name as alias so existing callers still work
  def eval_status_badge(assigns), do: eval_status_pill(assigns)

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

  defp eval_progress_color(:exceeds), do: "bg-success"
  defp eval_progress_color(:meets), do: "bg-success"
  defp eval_progress_color(:approaching), do: "bg-warning"
  defp eval_progress_color(:below), do: "bg-error"
  defp eval_progress_color(_), do: "bg-primary"
end
