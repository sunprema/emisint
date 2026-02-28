defmodule EmisintWeb.Growth.MonitorLive do
  use EmisintWeb, :live_view

  require Ash.Query

  @windows [:fall, :winter, :spring]

  def mount(%{"school_id" => school_id}, _session, socket) do
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
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-5xl mx-auto space-y-8">
        <%!-- Header --%>
        <div class="flex items-center gap-3">
          <.link
            navigate={~p"/schools/#{@school.id}"}
            class="p-2 hover:bg-base-200 transition-colors text-base-content/60 hover:text-base-content"
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <div class="flex items-center gap-4">
            <div class="p-2.5 bg-primary/10 border border-primary/20">
              <.icon name="hero-arrow-trending-up" class="size-6 text-primary" />
            </div>
            <div>
              <h1 class="text-2xl font-bold tracking-tight">Growth Monitor</h1>
              <p class="text-sm text-base-content/50 mt-0.5">{@school.name}</p>
            </div>
          </div>
        </div>

        <%!-- Controls row --%>
        <div class="flex flex-wrap gap-4 items-end">
          <div class="space-y-1.5">
            <label class="text-xs font-medium text-base-content/50 uppercase tracking-wider">
              Academic Year
            </label>
            <select
              class="border border-base-300 bg-base-100 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/25 focus:border-primary transition-all"
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

          <div class="space-y-1.5">
            <label class="text-xs font-medium text-base-content/50 uppercase tracking-wider">
              Testing Window
            </label>
            <div class="flex border border-base-300 overflow-hidden bg-base-100">
              <button
                :for={window <- @windows}
                phx-click="select_window"
                phx-value-window={window}
                class={[
                  "px-4 py-2 text-sm font-medium transition-colors",
                  @selected_window == window &&
                    "bg-primary text-primary-content",
                  @selected_window != window &&
                    "text-base-content/60 hover:bg-base-200"
                ]}
              >
                {String.capitalize(to_string(window))}
              </button>
            </div>
          </div>
        </div>

        <%!-- SGP subject cards --%>
        <div :if={@subjects != []} class="grid grid-cols-2 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          <.subject_sgp_card
            :for={subject <- @subjects}
            subject={subject}
            snapshots={@window_snaps}
          />
        </div>

        <%!-- No data --%>
        <div
          :if={@window_snaps == []}
          class="bg-base-100 border border-base-200 flex flex-col items-center justify-center py-16 text-center"
        >
          <div class="p-3 bg-base-200 mb-3">
            <.icon name="hero-arrow-trending-up" class="size-7 text-base-content/25" />
          </div>
          <p class="text-sm font-medium text-base-content/40">No growth data for this window</p>
          <p class="text-xs text-base-content/30 mt-1">
            Upload assessment data with SGP scores to populate this view.
          </p>
        </div>

        <%!-- Grade breakdown table --%>
        <div
          :if={@grade_levels != []}
          class="bg-base-100 border border-base-200 overflow-hidden"
        >
          <div class="px-6 py-4 border-b border-base-200">
            <h2 class="font-semibold">Growth by Grade</h2>
          </div>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-base-200 bg-base-50/50">
                  <th class="text-left px-6 py-3 text-xs font-medium text-base-content/40 uppercase tracking-wider">
                    Grade
                  </th>
                  <th
                    :for={subject <- @subjects}
                    class="text-center px-4 py-3 text-xs font-medium text-base-content/40 uppercase tracking-wider capitalize"
                  >
                    {subject}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-base-200">
                <tr :for={grade <- @grade_levels} class="hover:bg-base-50 transition-colors">
                  <td class="px-6 py-3 font-medium">{format_grade(grade)}</td>
                  <td :for={subject <- @subjects} class="px-4 py-3 text-center">
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

        <%!-- SGP Legend --%>
        <div class="border border-base-200 bg-base-50/50 px-5 py-4">
          <h3 class="text-xs font-semibold text-base-content/40 uppercase tracking-wider mb-3">
            SGP Benchmark Guide
          </h3>
          <div class="flex flex-wrap gap-4 text-sm">
            <span class="flex items-center gap-2">
              <span class="size-2.5 rounded-full bg-success inline-block shrink-0"></span>
              <span class="text-base-content/60">≥ 50th — At/Above Target</span>
            </span>
            <span class="flex items-center gap-2">
              <span class="size-2.5 rounded-full bg-warning inline-block shrink-0"></span>
              <span class="text-base-content/60">40–49 — Approaching</span>
            </span>
            <span class="flex items-center gap-2">
              <span class="size-2.5 rounded-full bg-error inline-block shrink-0"></span>
              <span class="text-base-content/60">
                &lt; 40 — Below Target
              </span>
            </span>
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
    <div class="bg-base-100 border border-base-200 p-5 flex flex-col items-center text-center">
      <span class="text-xs font-medium text-base-content/40 uppercase tracking-wider capitalize mb-3">
        {@subject}
      </span>
      <div
        :if={@median_sgp}
        class={["text-4xl font-bold tracking-tight", sgp_text_color(@median_sgp)]}
      >
        {Decimal.round(@median_sgp, 0) |> Decimal.to_string()}
      </div>
      <div :if={@median_sgp} class="text-xs text-base-content/40 mt-1">Median SGP</div>
      <div :if={is_nil(@median_sgp)} class="text-3xl font-bold text-base-content/20 mt-1">—</div>
      <div
        :if={@median_sgp}
        class={[
          "mt-3 px-2.5 py-1 rounded-full text-xs font-medium",
          sgp_pill_class(@median_sgp)
        ]}
      >
        {sgp_label(@median_sgp)}
      </div>
    </div>
    """
  end

  def sgp_cell(assigns) do
    ~H"""
    <div :if={@value} class="flex flex-col items-center gap-0.5">
      <span class={["font-bold", sgp_text_color(@value)]}>
        {Decimal.round(@value, 0) |> Decimal.to_string()}
      </span>
      <span class="text-xs text-base-content/30">n={@count}</span>
    </div>
    <span :if={is_nil(@value)} class="text-base-content/25">—</span>
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

  defp sgp_pill_class(d) do
    val = Decimal.to_float(d)

    cond do
      val >= 50 -> "bg-success/15 text-success"
      val >= 40 -> "bg-warning/15 text-warning"
      true -> "bg-error/15 text-error"
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
