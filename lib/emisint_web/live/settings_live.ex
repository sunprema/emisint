defmodule EmisintWeb.SettingsLive do
  use EmisintWeb, :live_view

  require Ash.Query

  on_mount {EmisintWeb.LiveUserAuth, :live_user_required}

  @threshold_components [
    {:overall, "Overall", "Bottom 5% Building", "CSI & ATS"},
    {:growth, "Growth", "Bottom 25% Components", "TSI & ATS"},
    {:proficiency, "Proficiency", "Bottom 25% Components", "TSI & ATS"},
    {:graduation, "Graduation Rate", "Bottom 25% Components", "TSI & ATS"},
    {:el_progress, "English Learner Progress", "Bottom 25% Components", "TSI & ATS"},
    {:school_quality, "School Quality & Student Success", "Bottom 25% Components", "TSI & ATS"},
    {:subject_participation, "Subject Test Participation", "Bottom 25% Components", "TSI & ATS"},
    {:el_participation, "English Learner Test Participation", "Bottom 25% Components",
     "TSI & ATS"}
  ]

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {available_years, selected_year, thresholds_map} =
      if user.role == :system_admin do
        years = load_available_years(user)
        years_with_data = load_years_with_data(user)
        selected = Enum.find(years, List.first(years), &(&1 in years_with_data))
        map = if selected, do: load_thresholds_map(selected, user), else: %{}
        {years, selected, map}
      else
        {[], nil, %{}}
      end

    socket =
      assign(socket,
        page_title: "Settings",
        threshold_components: @threshold_components,
        available_threshold_years: available_years,
        selected_threshold_year: selected_year,
        thresholds_map: thresholds_map,
        threshold_edit_mode: false
      )

    {:ok, socket}
  end

  def handle_event("select_threshold_year", %{"year" => year}, socket) do
    user = socket.assigns.current_user
    thresholds_map = load_thresholds_map(year, user)

    {:noreply,
     assign(socket,
       selected_threshold_year: year,
       thresholds_map: thresholds_map,
       threshold_edit_mode: false
     )}
  end

  def handle_event("edit_thresholds", _params, socket) do
    {:noreply, assign(socket, threshold_edit_mode: true)}
  end

  def handle_event("cancel_threshold_edit", _params, socket) do
    {:noreply, assign(socket, threshold_edit_mode: false)}
  end

  def handle_event("save_thresholds", %{"thresholds" => params}, socket) do
    user = socket.assigns.current_user
    year = socket.assigns.selected_threshold_year

    results =
      Enum.map(@threshold_components, fn {component, _label, _type, _designation} ->
        raw = Map.get(params, Atom.to_string(component), "")

        case Decimal.parse(raw) do
          {value, ""} ->
            Emisint.Assessments.upsert_mde_index_threshold(
              %{school_year: year, component: component, threshold_value: value},
              actor: user,
              authorize?: true
            )

          _ ->
            {:error, "Invalid value for #{component}: #{inspect(raw)}"}
        end
      end)

    errors = Enum.filter(results, fn r -> match?({:error, _}, r) end)

    if errors == [] do
      thresholds_map = load_thresholds_map(year, user)

      {:noreply,
       socket
       |> put_flash(:info, "Thresholds saved successfully.")
       |> assign(threshold_edit_mode: false, thresholds_map: thresholds_map)}
    else
      {:noreply, put_flash(socket, :error, "Failed to save one or more thresholds.")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="p-6 max-w-3xl mx-auto space-y-6">
        <div>
          <h1 class="text-2xl font-bold">Settings</h1>
          <p class="text-base-content/60 text-sm mt-1">Manage your preferences.</p>
        </div>

        <div class="bg-base-100 border border-base-200 rounded-xl divide-y divide-base-200">
          <%!-- Theme --%>
          <div class="flex items-center justify-between px-5 py-4">
            <div>
              <div class="font-medium text-sm">Theme</div>
              <div class="text-xs text-base-content/50 mt-0.5">
                Choose between system, light, or dark mode.
              </div>
            </div>
            <Layouts.theme_toggle />
          </div>
        </div>

        <%!-- MDE Index Thresholds — system_admin only --%>
        <div :if={@current_user.role == :system_admin} class="space-y-4">
          <div class="flex items-center justify-between">
            <div>
              <h2 class="text-lg font-semibold">MDE Index Thresholds</h2>
              <p class="text-sm text-base-content/60">
                Annual identification cutoff scores published by MDE.
              </p>
            </div>

            <div class="flex items-center gap-3">
              <form>
                <select
                  :if={length(@available_threshold_years) > 0}
                  class="select select-sm select-bordered"
                  phx-change="select_threshold_year"
                  name="year"
                >
                  <option
                    :for={y <- @available_threshold_years}
                    value={y}
                    selected={y == @selected_threshold_year}
                  >
                    {y}
                  </option>
                </select>
              </form>

              <button
                :if={not @threshold_edit_mode}
                class="btn btn-sm btn-outline"
                phx-click="edit_thresholds"
              >
                Edit
              </button>
            </div>
          </div>

          <div class="bg-base-100 border border-base-200 rounded-xl overflow-hidden">
            <%!-- Read-only table --%>
            <table :if={not @threshold_edit_mode} class="table table-sm w-full">
              <thead>
                <tr class="text-xs text-base-content/50 border-b border-base-200">
                  <th class="px-4 py-2 text-left">Component</th>
                  <th class="px-4 py-2 text-left">Type</th>
                  <th class="px-4 py-2 text-left">Designation</th>
                  <th class="px-4 py-2 text-right">Threshold</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={{component, label, type, designation} <- @threshold_components}
                  class="border-t border-base-200 hover:bg-base-200/30"
                >
                  <td class="px-4 py-2 text-sm font-medium">{label}</td>
                  <td class="px-4 py-2 text-sm text-base-content/70">{type}</td>
                  <td class="px-4 py-2 text-sm text-base-content/70">{designation}</td>
                  <td class="px-4 py-2 text-sm text-right font-mono">
                    {Map.get(@thresholds_map, component, "0.00")}
                  </td>
                </tr>
              </tbody>
            </table>

            <%!-- Edit form --%>
            <form :if={@threshold_edit_mode} phx-submit="save_thresholds">
              <table class="table table-sm w-full">
                <thead>
                  <tr class="text-xs text-base-content/50 border-b border-base-200">
                    <th class="px-4 py-2 text-left">Component</th>
                    <th class="px-4 py-2 text-left">Type</th>
                    <th class="px-4 py-2 text-left">Designation</th>
                    <th class="px-4 py-2 text-right">Threshold</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={{component, label, type, designation} <- @threshold_components}
                    class="border-t border-base-200"
                  >
                    <td class="px-4 py-2 text-sm font-medium">{label}</td>
                    <td class="px-4 py-2 text-sm text-base-content/70">{type}</td>
                    <td class="px-4 py-2 text-sm text-base-content/70">{designation}</td>
                    <td class="px-4 py-2 text-right">
                      <input
                        type="number"
                        step="0.01"
                        name={"thresholds[#{component}]"}
                        value={Map.get(@thresholds_map, component, "")}
                        class="input input-sm input-bordered w-28 text-right font-mono"
                        placeholder="0.00"
                        required
                      />
                    </td>
                  </tr>
                </tbody>
              </table>

              <div class="flex justify-end gap-2 px-4 py-3 border-t border-base-200">
                <button
                  type="button"
                  class="btn btn-sm btn-ghost"
                  phx-click="cancel_threshold_edit"
                >
                  Cancel
                </button>
                <button type="submit" class="btn btn-sm btn-primary">
                  Save
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_years_with_data(user) do
    Emisint.Assessments.MdeIndexThreshold
    |> Ash.Query.select([:school_year])
    |> Ash.read!(actor: user, authorize?: true)
    |> Enum.map(& &1.school_year)
    |> Enum.uniq()
  end

  defp load_available_years(user) do
    index_years =
      Emisint.Assessments.MdeSchoolIndexResult
      |> Ash.Query.select([:school_year])
      |> Ash.read!(actor: user, authorize?: true)
      |> Enum.map(& &1.school_year)

    threshold_years =
      Emisint.Assessments.MdeIndexThreshold
      |> Ash.Query.select([:school_year])
      |> Ash.read!(actor: user, authorize?: true)
      |> Enum.map(& &1.school_year)

    (index_years ++ threshold_years ++ recent_school_years())
    |> Enum.uniq()
    |> Enum.sort(:desc)
  end

  # Generates the last 6 school years so admins can always enter thresholds
  # for prior years even before any data exists. Format: "YYYY-YYYY".
  defp recent_school_years do
    {current_year, current_month, _} = Date.utc_today() |> Date.to_erl()
    # If before September, the current school year started last calendar year
    start_year = if current_month >= 9, do: current_year, else: current_year - 1

    Enum.map(0..5, fn offset ->
      y = start_year - offset
      "#{y}-#{y + 1}"
    end)
  end

  defp load_thresholds_map(year, user) do
    Emisint.Assessments.MdeIndexThreshold
    |> Ash.Query.filter(school_year == ^year)
    |> Ash.read!(actor: user, authorize?: true)
    |> Map.new(fn t -> {t.component, t.threshold_value} end)
  end
end
