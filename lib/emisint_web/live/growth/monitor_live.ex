defmodule EmisintWeb.Growth.MonitorLive do
  use EmisintWeb, :live_view

  require Ash.Query

  @windows [:fall, :winter, :spring]

  def mount(%{"school_id" => school_id}, _session, socket) do
    user = socket.assigns.current_user
    oid = user.organization_id
    scope = socket.assigns.scope

    school = Emisint.Accounts.get_school!(school_id, scope: scope)
    academic_years = Emisint.Registry.list_academic_years!(scope: scope)
    active_year = Enum.find(academic_years, & &1.active) || List.first(academic_years)

    snapshots =
      if active_year,
        do: load_grade_snapshots(school_id, active_year.id, scope),
        else: []

    {:ok,
     socket
     |> assign(:page_title, "#{school.name} — Growth")
     |> assign(:school, school)
     |> assign(:academic_years, academic_years)
     |> assign(:selected_year_id, active_year && active_year.id)
     |> assign(:selected_window, :spring)
     |> assign(:snapshots, snapshots)
     |> assign(:windows, @windows)}
  end

  def handle_event("select_year", %{"year_id" => year_id}, socket) do
    user = socket.assigns.current_user
    oid = user.organization_id
    scope = socket.assigns.scope

    snapshots = load_grade_snapshots(socket.assigns.school.id, year_id, scope)

    {:noreply,
     socket
     |> assign(:selected_year_id, year_id)
     |> assign(:snapshots, snapshots)}
  end

  def handle_event("select_window", %{"window" => window}, socket) do
    atom = String.to_existing_atom(window)

    if atom in @windows do
      {:noreply, assign(socket, :selected_window, atom)}
    else
      {:noreply, socket}
    end
  end

  def render(assigns) do
    window_snaps =
      Enum.filter(assigns.snapshots, &(&1.testing_window == assigns.selected_window))

    subjects = window_snaps |> Enum.map(& &1.subject) |> Enum.uniq() |> Enum.sort()

    grade_levels =
      window_snaps
      |> Enum.map(& &1.grade_level)
      |> Enum.reject(&(&1 == "all"))
      |> Enum.uniq()
      |> Enum.sort()

    assigns =
      assigns
      |> assign(:window_snaps, window_snaps)
      |> assign(:subjects, subjects)
      |> assign(:grade_levels, grade_levels)

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <%!-- Header --%>
        <div class="flex items-center gap-3 flex-wrap">
          <.link navigate={~p"/schools/#{@school.id}"} class="btn btn-ghost btn-sm btn-circle">
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <div>
            <h1 class="text-2xl font-bold">Growth Monitor</h1>
            <p class="text-base-content/60 text-sm">{@school.name}</p>
          </div>
        </div>

        <%!-- Selectors --%>
        <div class="flex flex-wrap gap-4 items-end">
          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Academic Year</span>
            </label>
            <select
              class="select select-bordered select-sm"
              phx-change="select_year"
              name="year_id"
            >
              <option
                :for={year <- @academic_years}
                value={year.id}
                selected={year.id == @selected_year_id}
              >
                {year.label}
              </option>
            </select>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Testing Window</span>
            </label>
            <div class="btn-group">
              <button
                :for={window <- @windows}
                phx-click="select_window"
                phx-value-window={window}
                class={["btn btn-sm", @selected_window == window && "btn-active"]}
              >
                {String.capitalize(to_string(window))}
              </button>
            </div>
          </div>
        </div>

        <%!-- SGP at-a-glance cards --%>
        <div :if={@subjects != []} class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          <.subject_sgp_card :for={subject <- @subjects} subject={subject} snapshots={@window_snaps} />
        </div>

        <%!-- No data state --%>
        <div :if={@window_snaps == []} class="card bg-base-200">
          <div class="card-body items-center py-12 text-center">
            <.icon name="hero-arrow-trending-up" class="size-12 text-base-content/30" />
            <p class="text-base-content/60 mt-2">No growth data for the selected window.</p>
            <p class="text-sm text-base-content/40">
              Upload assessment data with SGP scores to populate this view.
            </p>
          </div>
        </div>

        <%!-- Grade-by-grade breakdown table --%>
        <div :if={@grade_levels != []} class="space-y-2">
          <h2 class="text-lg font-semibold">Growth by Grade</h2>
          <div class="overflow-x-auto">
            <table class="table table-sm table-zebra bg-base-100 rounded-lg shadow-sm">
              <thead>
                <tr>
                  <th>Grade</th>
                  <th :for={subject <- @subjects} class="text-center capitalize">{subject}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={grade <- @grade_levels}>
                  <td class="font-medium">{format_grade(grade)}</td>
                  <td :for={subject <- @subjects} class="text-center">
                    <.sgp_cell
                      value={get_sgp(grade, subject, @window_snaps)}
                      count={get_count(grade, subject, @window_snaps)}
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- SGP Benchmark legend --%>
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-4">
            <h3 class="text-sm font-semibold mb-2">SGP Benchmark Guide</h3>
            <div class="flex flex-wrap gap-3 text-sm">
              <span class="flex items-center gap-1.5">
                <span class="w-3 h-3 rounded-full bg-success inline-block"></span>
                ≥ 50th — At/Above Target
              </span>
              <span class="flex items-center gap-1.5">
                <span class="w-3 h-3 rounded-full bg-warning inline-block"></span> 40–49 — Approaching
              </span>
              <span class="flex items-center gap-1.5">
                <span class="w-3 h-3 rounded-full bg-error inline-block"></span>
                &lt; 40 — Below Target
              </span>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def subject_sgp_card(assigns) do
    snaps =
      Enum.filter(assigns.snapshots, &(&1.subject == assigns.subject and &1.grade_level == "all"))

    median =
      case snaps do
        [snap | _] -> snap.median_sgp
        [] -> nil
      end

    assigns = assign(assigns, :median_sgp, median)

    ~H"""
    <div class="card bg-base-100 shadow-sm border border-base-200">
      <div class="card-body p-4 items-center text-center">
        <h3 class="font-semibold capitalize">{@subject}</h3>
        <div :if={@median_sgp} class={["text-3xl font-bold mt-1", sgp_text_color(@median_sgp)]}>
          {Decimal.round(@median_sgp, 0) |> Decimal.to_string()}
        </div>
        <div :if={@median_sgp} class="text-xs text-base-content/60">Median SGP</div>
        <div :if={is_nil(@median_sgp)} class="text-2xl font-bold text-base-content/30 mt-1">—</div>
        <div :if={@median_sgp} class={["badge badge-sm mt-1", sgp_badge_class(@median_sgp)]}>
          {sgp_label(@median_sgp)}
        </div>
      </div>
    </div>
    """
  end

  def sgp_cell(assigns) do
    ~H"""
    <div :if={@value} class="flex flex-col items-center">
      <span class={["font-bold text-sm", sgp_text_color(@value)]}>
        {Decimal.round(@value, 0) |> Decimal.to_string()}
      </span>
      <span class="text-xs text-base-content/40">n={@count}</span>
    </div>
    <span :if={is_nil(@value)} class="text-base-content/30 text-sm">—</span>
    """
  end

  # --- Helpers ---

  defp load_grade_snapshots(school_id, year_id, scope) do
    Emisint.Analytics.PerformanceSnapshot
    |> Ash.Query.filter(
      school_id == ^school_id and
        academic_year_id == ^year_id and
        snapshot_type == :by_grade
    )
    |> Ash.read!(scope: scope)
  end

  defp get_sgp(grade, subject, snapshots) do
    case Enum.find(snapshots, &(&1.grade_level == grade and &1.subject == subject)) do
      nil -> nil
      snap -> snap.median_sgp
    end
  end

  defp get_count(grade, subject, snapshots) do
    case Enum.find(snapshots, &(&1.grade_level == grade and &1.subject == subject)) do
      nil -> 0
      snap -> snap.student_count
    end
  end

  defp format_grade("all"), do: "All"
  defp format_grade(g), do: String.upcase(g)

  defp sgp_text_color(d) do
    val = Decimal.to_float(d)

    cond do
      val >= 50 -> "text-success"
      val >= 40 -> "text-warning"
      true -> "text-error"
    end
  end

  defp sgp_badge_class(d) do
    val = Decimal.to_float(d)

    cond do
      val >= 50 -> "badge-success"
      val >= 40 -> "badge-warning"
      true -> "badge-error"
    end
  end

  defp sgp_label(d) do
    val = Decimal.to_float(d)

    cond do
      val >= 50 -> "On Track"
      val >= 40 -> "Approaching"
      true -> "Below Target"
    end
  end
end
