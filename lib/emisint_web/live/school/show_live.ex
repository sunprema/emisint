defmodule EmisintWeb.School.ShowLive do
  use EmisintWeb, :live_view

  require Ash.Query

  on_mount {EmisintWeb.LiveUserAuth, :live_user_required}

  def mount(%{"id" => school_id}, _session, socket) do
    user = socket.assigns.current_user
    oid = user.organization_id

    school = Emisint.Accounts.get_school!(school_id, tenant: oid, actor: user)

    academic_years = Emisint.Registry.list_academic_years!(tenant: oid, actor: user)
    active_year = Enum.find(academic_years, & &1.active) || List.first(academic_years)

    all_snapshots = load_snapshots(school_id, oid, user)
    goals_with_evals = load_goals_with_evals(school_id, oid, user)
    triggers = load_triggers(school_id, oid, user)

    {:ok,
     socket
     |> assign(:page_title, school.name)
     |> assign(:school, school)
     |> assign(:active_tab, :proficiency)
     |> assign(:academic_years, academic_years)
     |> assign(:selected_year_id, active_year && active_year.id)
     |> assign(:all_snapshots, all_snapshots)
     |> assign(:goals_with_evals, goals_with_evals)
     |> assign(:triggers, triggers)
     |> assign(:tabs, [:proficiency, :growth, :compliance, :interventions])}
  end

  def handle_params(%{"tab" => tab}, _url, socket) when tab in ["proficiency", "growth", "compliance", "interventions"] do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center gap-3">
        <.link navigate={~p"/dashboard"} class="btn btn-ghost btn-sm btn-circle">
          <.icon name="hero-arrow-left" class="size-5" />
        </.link>
        <div>
          <h1 class="text-2xl font-bold">{@school.name}</h1>
          <p class="text-base-content/60 text-sm">
            {@school.city} · MDE {@school.mde_building_code}
          </p>
        </div>
      </div>

      <%!-- Quick-link buttons to detail pages --%>
      <div class="flex flex-wrap gap-2">
        <.link
          navigate={~p"/compliance/#{@school.id}"}
          class="btn btn-outline btn-sm gap-1"
        >
          <.icon name="hero-clipboard-document-check" class="size-4" />
          Schedule 7-1 Tracker
        </.link>
        <.link
          navigate={~p"/growth/#{@school.id}"}
          class="btn btn-outline btn-sm gap-1"
        >
          <.icon name="hero-arrow-trending-up" class="size-4" />
          Growth Monitor
        </.link>
      </div>

      <%!-- Tab bar --%>
      <div role="tablist" class="tabs tabs-bordered">
        <.link
          :for={tab <- @tabs}
          patch={~p"/schools/#{@school.id}?tab=#{tab}"}
          role="tab"
          class={["tab", @active_tab == tab && "tab-active"]}
        >
          {tab_label(tab)}
        </.link>
      </div>

      <%!-- Tab panels --%>
      <div :if={@active_tab == :proficiency}>
        <.proficiency_tab snapshots={school_wide_snapshots(@all_snapshots)} />
      </div>

      <div :if={@active_tab == :growth}>
        <.growth_tab snapshots={by_grade_snapshots(@all_snapshots)} />
      </div>

      <div :if={@active_tab == :compliance}>
        <.compliance_tab goals_with_evals={@goals_with_evals} school={@school} />
      </div>

      <div :if={@active_tab == :interventions}>
        <.interventions_tab triggers={@triggers} />
      </div>
    </div>
    """
  end

  # --- Tab Components ---

  def proficiency_tab(assigns) do
    subjects = assigns.snapshots |> Enum.map(& &1.subject) |> Enum.uniq() |> Enum.sort()
    assigns = assign(assigns, :subjects, subjects)

    ~H"""
    <div class="space-y-4">
      <h2 class="text-lg font-semibold">Proficiency Rates by Subject</h2>

      <div :if={@snapshots == []} class="card bg-base-200">
        <div class="card-body items-center py-8 text-center">
          <p class="text-base-content/60">No proficiency data available yet.</p>
          <p class="text-sm text-base-content/40">Upload assessment data to populate this view.</p>
        </div>
      </div>

      <div :if={@snapshots != []} class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
        <div :for={subject <- @subjects} class="card bg-base-100 shadow-sm border border-base-200">
          <div class="card-body p-4">
            <h3 class="font-semibold capitalize">{subject}</h3>
            <div
              :for={snap <- Enum.filter(@snapshots, &(&1.subject == subject))}
              class="mt-2"
            >
              <div class="flex justify-between items-center text-sm mb-1">
                <span class="capitalize text-base-content/70">{snap.testing_window}</span>
                <span class="font-bold">{format_pct(snap.proficiency_rate)}</span>
              </div>
              <progress
                class={["progress w-full", proficiency_color(snap.proficiency_rate)]}
                value={snap.proficiency_rate && Decimal.to_float(snap.proficiency_rate)}
                max="1"
              >
              </progress>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def growth_tab(assigns) do
    grade_levels =
      assigns.snapshots |> Enum.map(& &1.grade_level) |> Enum.uniq() |> Enum.reject(&(&1 == "all")) |> Enum.sort()

    assigns = assign(assigns, :grade_levels, grade_levels)

    ~H"""
    <div class="space-y-4">
      <h2 class="text-lg font-semibold">Growth by Grade Level</h2>

      <div :if={@snapshots == []} class="card bg-base-200">
        <div class="card-body items-center py-8 text-center">
          <p class="text-base-content/60">No growth data available yet.</p>
          <p class="text-sm text-base-content/40">Upload assessment data with SGP scores to populate this view.</p>
        </div>
      </div>

      <div :if={@snapshots != []} class="overflow-x-auto">
        <table class="table table-sm table-zebra">
          <thead>
            <tr>
              <th>Grade</th>
              <th>Subject</th>
              <th>Window</th>
              <th class="text-right">Median SGP</th>
              <th class="text-right">Avg SGP</th>
              <th class="text-right">Students</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={snap <- Enum.sort_by(@snapshots, &{&1.grade_level, &1.subject})}>
              <td class="font-medium">{format_grade(snap.grade_level)}</td>
              <td class="capitalize">{snap.subject}</td>
              <td class="capitalize">{snap.testing_window}</td>
              <td class="text-right">
                <span class={["font-bold", sgp_color(snap.median_sgp)]}>
                  {format_sgp(snap.median_sgp)}
                </span>
              </td>
              <td class="text-right text-base-content/70">{format_sgp(snap.average_sgp)}</td>
              <td class="text-right text-base-content/70">{snap.student_count}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  def compliance_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-semibold">Schedule 7-1 Goals</h2>
        <.link navigate={~p"/compliance/#{@school.id}"} class="btn btn-primary btn-sm gap-1">
          <.icon name="hero-arrow-right" class="size-4" /> Full Tracker
        </.link>
      </div>

      <div :if={@goals_with_evals == []} class="card bg-base-200">
        <div class="card-body items-center py-8 text-center">
          <p class="text-base-content/60">No compliance goals configured for this school.</p>
        </div>
      </div>

      <div :if={@goals_with_evals != []} class="space-y-2">
        <div :for={{goal, eval} <- @goals_with_evals} class="card bg-base-100 shadow-sm border border-base-200">
          <div class="card-body p-4 flex-row items-center gap-4">
            <div class="flex-1 min-w-0">
              <div class="font-medium truncate">{goal.title}</div>
              <div class="text-sm text-base-content/60 capitalize mt-0.5">
                {goal.goal_type |> to_string() |> String.replace("_", " ")} · {goal.subject}
              </div>
            </div>
            <div class="shrink-0">
              <.status_badge status={eval && eval.status} />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def interventions_tab(assigns) do
    active = Enum.filter(assigns.triggers, &(&1.status == :active))
    assigns = assign(assigns, :active_triggers, active)

    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-semibold">Active Interventions</h2>
        <span :if={@active_triggers != []} class="badge badge-error">{length(@active_triggers)}</span>
      </div>

      <div :if={@active_triggers == []} class="card bg-base-200">
        <div class="card-body items-center py-8 text-center">
          <.icon name="hero-check-circle" class="size-12 text-success" />
          <p class="text-base-content/60 mt-2">No active intervention triggers. Keep it up!</p>
        </div>
      </div>

      <div :if={@active_triggers != []} class="space-y-2">
        <div
          :for={trigger <- Enum.sort_by(@active_triggers, &{severity_order(&1.severity), &1.triggered_at}, :asc)}
          class="card bg-base-100 shadow-sm border border-base-200"
        >
          <div class="card-body p-4 flex-row items-start gap-3">
            <div class={["badge badge-sm mt-0.5 shrink-0", severity_badge_class(trigger.severity)]}>
              {trigger.severity}
            </div>
            <div class="flex-1 min-w-0">
              <div class="font-medium capitalize">
                {trigger.trigger_type |> to_string() |> String.replace("_", " ")}
              </div>
              <div class="text-sm text-base-content/60 mt-0.5">
                Triggered {Calendar.strftime(trigger.triggered_at, "%b %d, %Y")}
              </div>
              <div :if={trigger.notes} class="text-sm mt-1 italic text-base-content/70">
                {trigger.notes}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def status_badge(assigns) do
    ~H"""
    <span :if={is_nil(@status)} class="badge badge-ghost badge-sm">No data</span>
    <span :if={@status == :exceeds} class="badge badge-success gap-1">
      <.icon name="hero-check-circle" class="size-3" /> Exceeds
    </span>
    <span :if={@status == :meets} class="badge badge-success badge-outline gap-1">
      <.icon name="hero-check" class="size-3" /> Meets
    </span>
    <span :if={@status == :approaching} class="badge badge-warning gap-1">
      <.icon name="hero-exclamation-triangle" class="size-3" /> Approaching
    </span>
    <span :if={@status == :below} class="badge badge-error gap-1">
      <.icon name="hero-x-circle" class="size-3" /> Below
    </span>
    <span :if={@status == :insufficient_data} class="badge badge-ghost badge-sm">Insufficient Data</span>
    """
  end

  # --- Private helpers ---

  defp load_snapshots(school_id, oid, user) do
    Emisint.Analytics.PerformanceSnapshot
    |> Ash.Query.filter(school_id == ^school_id)
    |> Ash.read!(tenant: oid, actor: user)
  end

  defp load_goals_with_evals(school_id, oid, user) do
    goals =
      Emisint.Compliance.Schedule71Goal
      |> Ash.Query.filter(school_id == ^school_id)
      |> Ash.read!(tenant: oid, actor: user)

    evaluations =
      Emisint.Compliance.GoalEvaluation
      |> Ash.read!(tenant: oid, actor: user)

    eval_by_goal = Map.new(evaluations, fn e -> {e.schedule71_goal_id, e} end)

    Enum.map(goals, fn goal -> {goal, Map.get(eval_by_goal, goal.id)} end)
  end

  defp load_triggers(school_id, oid, user) do
    Emisint.Analytics.InterventionTrigger
    |> Ash.Query.filter(school_id == ^school_id)
    |> Ash.read!(tenant: oid, actor: user)
  end

  defp school_wide_snapshots(snapshots) do
    Enum.filter(snapshots, &(&1.snapshot_type == :school_wide))
  end

  defp by_grade_snapshots(snapshots) do
    Enum.filter(snapshots, &(&1.snapshot_type == :by_grade))
  end

  defp tab_label(:proficiency), do: "Proficiency"
  defp tab_label(:growth), do: "Growth"
  defp tab_label(:compliance), do: "Compliance"
  defp tab_label(:interventions), do: "Interventions"

  defp format_pct(nil), do: "—"

  defp format_pct(d) do
    pct = Decimal.mult(d, 100) |> Decimal.round(1) |> Decimal.to_string()
    "#{pct}%"
  end

  defp format_sgp(nil), do: "—"
  defp format_sgp(d), do: Decimal.round(d, 1) |> Decimal.to_string()

  defp format_grade("all"), do: "All"
  defp format_grade(g), do: String.upcase(g)

  defp proficiency_color(nil), do: "progress-primary"

  defp proficiency_color(d) do
    val = Decimal.to_float(d)
    cond do
      val >= 0.6 -> "progress-success"
      val >= 0.4 -> "progress-warning"
      true -> "progress-error"
    end
  end

  defp sgp_color(nil), do: ""

  defp sgp_color(d) do
    val = Decimal.to_float(d)
    cond do
      val >= 50 -> "text-success"
      val >= 40 -> "text-warning"
      true -> "text-error"
    end
  end

  defp severity_order(:high), do: 0
  defp severity_order(:medium), do: 1
  defp severity_order(:low), do: 2

  defp severity_badge_class(:high), do: "badge-error"
  defp severity_badge_class(:medium), do: "badge-warning"
  defp severity_badge_class(:low), do: "badge-info"

end
