defmodule EmisintWeb.School.HealthScoreLive do
  use EmisintWeb, :live_view

  require Ash.Query

  on_mount {EmisintWeb.LiveUserAuth, :live_user_required}

  alias Emisint.Analytics.HealthScore

  def mount(_params, _session, socket) do
    scope = socket.assigns.scope

    socket = assign(socket, scored_schools: [], page_title: "School Health Scores")

    if connected?(socket) do
      # Four independent queries — run in parallel.
      schools_task = Task.async(fn -> Ash.read!(Emisint.Accounts.School, scope: scope) end)

      snapshots_task =
        Task.async(fn ->
          Emisint.Analytics.PerformanceSnapshot
          |> Ash.Query.filter(snapshot_type == :school_wide)
          |> Ash.read!(scope: scope)
        end)

      evals_task =
        Task.async(fn ->
          Emisint.Compliance.GoalEvaluation
          |> Ash.Query.load(:schedule71_goal)
          |> Ash.read!(scope: scope)
        end)

      triggers_task =
        Task.async(fn ->
          Emisint.Analytics.InterventionTrigger
          |> Ash.Query.filter(status == :active)
          |> Ash.read!(scope: scope)
        end)

      schools = Task.await(schools_task)
      snapshots = Task.await(snapshots_task)
      evals = Task.await(evals_task)
      triggers = Task.await(triggers_task)

      snaps_by_school = Enum.group_by(snapshots, & &1.school_id)
      evals_by_school =
        Enum.group_by(evals, fn e ->
          if e.schedule71_goal, do: e.schedule71_goal.school_id, else: nil
        end)
      triggers_by_school = Enum.group_by(triggers, & &1.school_id)

      scored_schools =
        schools
        |> Enum.map(fn school ->
          result =
            HealthScore.compute(
              school.id,
              Map.get(snaps_by_school, school.id, []),
              Map.get(evals_by_school, school.id, []),
              Map.get(triggers_by_school, school.id, [])
            )

          {school, result}
        end)
        |> Enum.sort_by(fn {_, r} -> r.score end, :desc)
        |> Enum.with_index(1)
        |> Enum.map(fn {{school, result}, rank} -> {rank, school, result} end)

      {:ok, assign(socket, :scored_schools, scored_schools)}
    else
      {:ok, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-5xl mx-auto space-y-8">
        <%!-- Header --%>
        <div class="flex items-center gap-4">
          <div class="p-2.5 bg-primary/10 border border-primary/20">
            <.icon name="hero-chart-bar" class="size-6 text-primary" />
          </div>
          <div>
            <h1 class="text-2xl font-bold tracking-tight">School Health Scores</h1>
            <p class="text-sm text-base-content/50 mt-0.5">
              Composite academic performance index across all academies
            </p>
          </div>
        </div>

        <%!-- Disclaimer banner --%>
        <div class="flex items-start gap-3 p-4 bg-warning/8 border border-warning/20 text-sm text-base-content/70">
          <.icon name="hero-information-circle" class="size-5 text-warning shrink-0 mt-0.5" />
          <span>
            <strong>Internal Tool:</strong>
            This score is an internal analytics tool and does not reflect official MDE ratings.
          </span>
        </div>

        <%!-- Empty state --%>
        <div
          :if={@scored_schools == []}
          class="bg-base-100 border border-base-200 flex flex-col items-center justify-center py-16 text-center"
        >
          <div class="p-3 bg-base-200 mb-3">
            <.icon name="hero-chart-bar" class="size-7 text-base-content/25" />
          </div>
          <p class="text-sm font-medium text-base-content/40">No schools found</p>
        </div>

        <%!-- Ranked table --%>
        <div :if={@scored_schools != []} class="bg-base-100 border border-base-200 overflow-hidden">
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-base-200 bg-base-50/50">
                  <th class="text-left px-5 py-3 text-xs font-medium text-base-content/40 uppercase tracking-wider w-12">
                    #
                  </th>
                  <th class="text-left px-5 py-3 text-xs font-medium text-base-content/40 uppercase tracking-wider">
                    School
                  </th>
                  <th class="text-center px-4 py-3 text-xs font-medium text-base-content/40 uppercase tracking-wider">
                    Grade
                  </th>
                  <th class="text-right px-5 py-3 text-xs font-medium text-base-content/40 uppercase tracking-wider">
                    Score
                  </th>
                  <th class="text-right px-5 py-3 text-xs font-medium text-base-content/40 uppercase tracking-wider hidden sm:table-cell">
                    Proficiency
                  </th>
                  <th class="text-right px-5 py-3 text-xs font-medium text-base-content/40 uppercase tracking-wider hidden sm:table-cell">
                    Growth
                  </th>
                  <th class="text-right px-5 py-3 text-xs font-medium text-base-content/40 uppercase tracking-wider hidden md:table-cell">
                    Compliance
                  </th>
                  <th class="text-right px-5 py-3 text-xs font-medium text-base-content/40 uppercase tracking-wider hidden md:table-cell">
                    Interventions
                  </th>
                  <th class="px-5 py-3"></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-base-200">
                <.school_row
                  :for={{rank, school, result} <- @scored_schools}
                  rank={rank}
                  school={school}
                  result={result}
                />
              </tbody>
            </table>
          </div>
        </div>

        <%!-- Grade legend --%>
        <div class="flex flex-wrap gap-4 text-xs text-base-content/50">
          <span class="flex items-center gap-1.5">
            <span class="inline-block px-2 py-0.5 rounded font-bold bg-success/15 text-success">
              A
            </span>
            80–100
          </span>
          <span class="flex items-center gap-1.5">
            <span class="inline-block px-2 py-0.5 rounded font-bold bg-info/15 text-info">B</span>
            65–79
          </span>
          <span class="flex items-center gap-1.5">
            <span class="inline-block px-2 py-0.5 rounded font-bold bg-warning/15 text-warning">
              C
            </span>
            50–64
          </span>
          <span class="flex items-center gap-1.5">
            <span class="inline-block px-2 py-0.5 rounded font-bold bg-orange-500/15 text-orange-600">
              D
            </span>
            35–49
          </span>
          <span class="flex items-center gap-1.5">
            <span class="inline-block px-2 py-0.5 rounded font-bold bg-error/15 text-error">F</span>
            0–34
          </span>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def school_row(assigns) do
    ~H"""
    <tr class="hover:bg-base-50 transition-colors">
      <td class="px-5 py-4">
        <span class={[
          "inline-flex items-center justify-center size-7 text-xs font-bold rounded",
          rank_badge_class(@rank)
        ]}>
          {@rank}
        </span>
      </td>
      <td class="px-5 py-4">
        <div class="font-medium">{@school.name}</div>
        <div class="text-xs text-base-content/50 mt-0.5">{@school.city || @school.county}</div>
      </td>
      <td class="px-4 py-4 text-center">
        <span class={[
          "inline-flex items-center justify-center px-3 py-1 text-sm font-bold rounded",
          grade_chip_class(@result.grade)
        ]}>
          {@result.grade}
        </span>
      </td>
      <td class="px-5 py-4 text-right">
        <div class="font-bold text-lg">{@result.score}</div>
        <div class="w-20 ml-auto mt-1 bg-base-200 rounded-full h-1.5">
          <div
            class={["h-1.5 rounded-full transition-all", score_bar_class(@result.score)]}
            style={"width: #{min(@result.score, 100)}%"}
          >
          </div>
        </div>
      </td>
      <td class="px-5 py-4 text-right hidden sm:table-cell">
        <span class="text-base-content/70">{format_pts(@result.proficiency_pts)}</span>
        <span class="text-xs text-base-content/30">/40</span>
      </td>
      <td class="px-5 py-4 text-right hidden sm:table-cell">
        <span class="text-base-content/70">{format_pts(@result.sgp_pts)}</span>
        <span class="text-xs text-base-content/30">/30</span>
      </td>
      <td class="px-5 py-4 text-right hidden md:table-cell">
        <span class="text-base-content/70">{format_pts(@result.compliance_pts)}</span>
        <span class="text-xs text-base-content/30">/20</span>
      </td>
      <td class="px-5 py-4 text-right hidden md:table-cell">
        <span class="text-base-content/70">{format_pts(@result.intervention_pts)}</span>
        <span class="text-xs text-base-content/30">/10</span>
      </td>
      <td class="px-5 py-4">
        <div class="flex items-center gap-2 justify-end">
          <.link
            navigate={~p"/schools/#{@school.id}"}
            class="flex items-center gap-1 text-xs font-medium text-primary hover:text-primary/80 transition-colors"
          >
            Detail <.icon name="hero-arrow-right" class="size-3" />
          </.link>
          <.link
            navigate={~p"/compliance/#{@school.id}"}
            class="flex items-center gap-1 text-xs text-base-content/40 hover:text-base-content transition-colors"
          >
            7-1 <.icon name="hero-clipboard-document-check" class="size-3" />
          </.link>
        </div>
      </td>
    </tr>
    """
  end

  # --- Private helpers ---

  defp rank_badge_class(1), do: "bg-yellow-400/20 text-yellow-600"
  defp rank_badge_class(2), do: "bg-slate-300/30 text-slate-500"
  defp rank_badge_class(3), do: "bg-orange-400/20 text-orange-600"
  defp rank_badge_class(_), do: "bg-base-200 text-base-content/50"

  defp grade_chip_class("A"), do: "bg-success/15 text-success"
  defp grade_chip_class("B"), do: "bg-info/15 text-info"
  defp grade_chip_class("C"), do: "bg-warning/15 text-warning"
  defp grade_chip_class("D"), do: "bg-orange-500/15 text-orange-600"
  defp grade_chip_class(_), do: "bg-error/15 text-error"

  defp score_bar_class(s) when s >= 80, do: "bg-success"
  defp score_bar_class(s) when s >= 65, do: "bg-info"
  defp score_bar_class(s) when s >= 50, do: "bg-warning"
  defp score_bar_class(s) when s >= 35, do: "bg-orange-500"
  defp score_bar_class(_), do: "bg-error"

  defp format_pts(pts), do: Float.round(pts, 1) |> to_string()
end
