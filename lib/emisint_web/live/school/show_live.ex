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

  def handle_params(%{"tab" => tab}, _url, socket)
      when tab in ["proficiency", "growth", "compliance", "interventions"] do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-5xl mx-auto space-y-8">
        <%!-- Header --%>
        <div class="flex items-start gap-3">
          <.link
            navigate={~p"/dashboard"}
            class="mt-1 p-2 hover:bg-base-200 transition-colors text-base-content/60 hover:text-base-content shrink-0"
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <div class="flex-1 min-w-0">
            <h1 class="text-2xl font-bold tracking-tight truncate">{@school.name}</h1>
            <p class="text-sm text-base-content/50 mt-0.5">
              {@school.city} · MDE {@school.mde_building_code}
            </p>
          </div>
          <%!-- Quick links --%>
          <div class="flex gap-2 shrink-0">
            <.link
              navigate={~p"/compliance/#{@school.id}"}
              class="flex items-center gap-1.5 px-3 py-2 border border-base-300 text-xs font-medium text-base-content/60 hover:border-primary/40 hover:text-primary transition-all"
            >
              <.icon name="hero-clipboard-document-check" class="size-3.5" /> Schedule 7-1
            </.link>
            <.link
              navigate={~p"/growth/#{@school.id}"}
              class="flex items-center gap-1.5 px-3 py-2 border border-base-300 text-xs font-medium text-base-content/60 hover:border-primary/40 hover:text-primary transition-all"
            >
              <.icon name="hero-arrow-trending-up" class="size-3.5" /> Growth
            </.link>
          </div>
        </div>

        <%!-- Tab bar --%>
        <div class="flex gap-1 p-1 bg-base-200 w-fit">
          <.link
            :for={tab <- @tabs}
            patch={~p"/schools/#{@school.id}?tab=#{tab}"}
            class={[
              "px-4 py-2 text-sm font-medium transition-all",
              @active_tab == tab &&
                "bg-base-100 text-base-content",
              @active_tab != tab &&
                "text-base-content/50 hover:text-base-content"
            ]}
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
    </Layouts.app>
    """
  end

  # --- Tab Components ---

  def proficiency_tab(assigns) do
    subjects = assigns.snapshots |> Enum.map(& &1.subject) |> Enum.uniq() |> Enum.sort()
    assigns = assign(assigns, :subjects, subjects)

    ~H"""
    <div class="space-y-5">
      <div
        :if={@snapshots == []}
        class="bg-base-100 border border-base-200 flex flex-col items-center justify-center py-14 text-center"
      >
        <div class="p-3 bg-base-200 mb-3">
          <.icon name="hero-chart-bar" class="size-6 text-base-content/25" />
        </div>
        <p class="text-sm font-medium text-base-content/40">No proficiency data yet</p>
        <p class="text-xs text-base-content/30 mt-1">Upload assessment data to populate this view.</p>
      </div>

      <div :if={@snapshots != []} class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
        <div
          :for={subject <- @subjects}
          class="bg-base-100 border border-base-200 p-5"
        >
          <h3 class="text-xs font-semibold text-base-content/40 uppercase tracking-wider capitalize mb-4">
            {subject}
          </h3>
          <div
            :for={snap <- Enum.filter(@snapshots, &(&1.subject == subject))}
            class="mb-3 last:mb-0"
          >
            <div class="flex justify-between items-baseline mb-1.5">
              <span class="text-xs capitalize text-base-content/50">{snap.testing_window}</span>
              <span class="text-sm font-bold">{format_pct(snap.proficiency_rate)}</span>
            </div>
            <div class="w-full bg-base-200 rounded-full h-1.5">
              <div
                class={["h-1.5 rounded-full transition-all", proficiency_color(snap.proficiency_rate)]}
                style={"width: #{snap.proficiency_rate && Float.round(Decimal.to_float(snap.proficiency_rate) * 100, 1)}%"}
              >
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def growth_tab(assigns) do
    grade_levels =
      assigns.snapshots
      |> Enum.map(& &1.grade_level)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == "all"))
      |> Enum.sort()

    assigns = assign(assigns, :grade_levels, grade_levels)

    ~H"""
    <div class="space-y-5">
      <div
        :if={@snapshots == []}
        class="bg-base-100 border border-base-200 flex flex-col items-center justify-center py-14 text-center"
      >
        <div class="p-3 bg-base-200 mb-3">
          <.icon name="hero-arrow-trending-up" class="size-6 text-base-content/25" />
        </div>
        <p class="text-sm font-medium text-base-content/40">No growth data yet</p>
        <p class="text-xs text-base-content/30 mt-1">
          Upload assessment data with SGP scores to populate this view.
        </p>
      </div>

      <div
        :if={@snapshots != []}
        class="bg-base-100 border border-base-200 overflow-hidden"
      >
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-base-200 bg-base-50/50">
                <th class="text-left px-5 py-3 text-xs font-medium text-base-content/40 uppercase tracking-wider">
                  Grade
                </th>
                <th class="text-left px-5 py-3 text-xs font-medium text-base-content/40 uppercase tracking-wider">
                  Subject
                </th>
                <th class="text-left px-5 py-3 text-xs font-medium text-base-content/40 uppercase tracking-wider">
                  Window
                </th>
                <th class="text-right px-5 py-3 text-xs font-medium text-base-content/40 uppercase tracking-wider">
                  Median SGP
                </th>
                <th class="text-right px-5 py-3 text-xs font-medium text-base-content/40 uppercase tracking-wider">
                  Avg SGP
                </th>
                <th class="text-right px-5 py-3 text-xs font-medium text-base-content/40 uppercase tracking-wider">
                  Students
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-200">
              <tr
                :for={snap <- Enum.sort_by(@snapshots, &{&1.grade_level, &1.subject})}
                class="hover:bg-base-50 transition-colors"
              >
                <td class="px-5 py-3 font-medium">{format_grade(snap.grade_level)}</td>
                <td class="px-5 py-3 capitalize text-base-content/70">{snap.subject}</td>
                <td class="px-5 py-3 capitalize text-base-content/70">{snap.testing_window}</td>
                <td class="px-5 py-3 text-right">
                  <span class={["font-bold", sgp_color(snap.median_sgp)]}>
                    {format_sgp(snap.median_sgp)}
                  </span>
                </td>
                <td class="px-5 py-3 text-right text-base-content/50">
                  {format_sgp(snap.average_sgp)}
                </td>
                <td class="px-5 py-3 text-right text-base-content/50">{snap.student_count}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  def compliance_tab(assigns) do
    ~H"""
    <div class="space-y-5">
      <div class="flex items-center justify-between">
        <h2 class="font-semibold">Schedule 7-1 Goals</h2>
        <.link
          navigate={~p"/compliance/#{@school.id}"}
          class="flex items-center gap-1.5 px-3 py-2 bg-primary text-primary-content text-xs font-medium hover:opacity-90 transition-opacity"
        >
          Full Tracker <.icon name="hero-arrow-right" class="size-3.5" />
        </.link>
      </div>

      <div
        :if={@goals_with_evals == []}
        class="bg-base-100 border border-base-200 flex flex-col items-center justify-center py-14 text-center"
      >
        <div class="p-3 bg-base-200 mb-3">
          <.icon name="hero-clipboard-document-list" class="size-6 text-base-content/25" />
        </div>
        <p class="text-sm font-medium text-base-content/40">No goals configured</p>
      </div>

      <div :if={@goals_with_evals != []} class="space-y-2">
        <div
          :for={{goal, eval} <- @goals_with_evals}
          class="flex items-center gap-4 p-4 bg-base-100 border border-base-200 hover:bg-base-50 transition-colors"
        >
          <div class="flex-1 min-w-0">
            <div class="font-medium text-sm truncate">{goal.title}</div>
            <div class="text-xs text-base-content/50 capitalize mt-0.5">
              {goal.goal_type |> to_string() |> String.replace("_", " ")} · {goal.subject}
            </div>
          </div>
          <div class="shrink-0">
            <.status_pill status={eval && eval.status} />
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
    <div class="space-y-5">
      <div class="flex items-center justify-between">
        <h2 class="font-semibold">Active Interventions</h2>
        <span
          :if={@active_triggers != []}
          class="flex items-center gap-1 px-2.5 py-1 rounded-full bg-error/10 text-error text-xs font-medium"
        >
          <.icon name="hero-bell-alert" class="size-3" /> {length(@active_triggers)}
        </span>
      </div>

      <div
        :if={@active_triggers == []}
        class="bg-base-100 border border-base-200 flex flex-col items-center justify-center py-14 text-center"
      >
        <div class="p-3 bg-success/10 mb-3">
          <.icon name="hero-check-circle" class="size-6 text-success" />
        </div>
        <p class="text-sm font-medium text-base-content/50">No active interventions</p>
        <p class="text-xs text-base-content/30 mt-1">Keep it up!</p>
      </div>

      <div :if={@active_triggers != []} class="space-y-2">
        <div
          :for={
            trigger <-
              Enum.sort_by(@active_triggers, &{severity_order(&1.severity), &1.triggered_at}, :asc)
          }
          class="flex items-start gap-3 p-4 bg-base-100 border border-base-200 hover:bg-base-50 transition-colors"
        >
          <div class={[
            "px-2.5 py-1 rounded-full text-xs font-medium shrink-0 mt-0.5 capitalize",
            severity_pill_class(trigger.severity)
          ]}>
            {trigger.severity}
          </div>
          <div class="flex-1 min-w-0">
            <div class="text-sm font-medium capitalize">
              {trigger.trigger_type |> to_string() |> String.replace("_", " ")}
            </div>
            <div class="text-xs text-base-content/50 mt-0.5">
              Triggered {Calendar.strftime(trigger.triggered_at, "%b %d, %Y")}
            </div>
            <div :if={trigger.notes} class="text-xs mt-1.5 italic text-base-content/60">
              {trigger.notes}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def status_pill(assigns) do
    ~H"""
    <span
      :if={is_nil(@status)}
      class="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium bg-base-200 text-base-content/40"
    >
      No data
    </span>
    <span
      :if={@status == :exceeds}
      class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-success/15 text-success"
    >
      <.icon name="hero-check-circle" class="size-3" /> Exceeds
    </span>
    <span
      :if={@status == :meets}
      class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-success/8 text-success border border-success/20"
    >
      <.icon name="hero-check" class="size-3" /> Meets
    </span>
    <span
      :if={@status == :approaching}
      class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-warning/15 text-warning"
    >
      <.icon name="hero-exclamation-triangle" class="size-3" /> Approaching
    </span>
    <span
      :if={@status == :below}
      class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-error/15 text-error"
    >
      <.icon name="hero-x-circle" class="size-3" /> Below
    </span>
    <span
      :if={@status == :insufficient_data}
      class="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium bg-base-200 text-base-content/40"
    >
      Insufficient Data
    </span>
    """
  end

  # Keep old name as alias
  def status_badge(assigns), do: status_pill(assigns)

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

  defp proficiency_color(nil), do: "bg-primary"

  defp proficiency_color(d) do
    val = Decimal.to_float(d)

    cond do
      val >= 0.6 -> "bg-success"
      val >= 0.4 -> "bg-warning"
      true -> "bg-error"
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

  defp severity_pill_class(:high), do: "bg-error/15 text-error"
  defp severity_pill_class(:medium), do: "bg-warning/15 text-warning"
  defp severity_pill_class(:low), do: "bg-info/15 text-info"
end
