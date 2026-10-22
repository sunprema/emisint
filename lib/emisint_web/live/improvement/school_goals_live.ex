defmodule EmisintWeb.Improvement.SchoolGoalsLive do
  @moduledoc """
  School goals dashboard (ND First pilot): goals, metrics, the selected
  seasonal period's actual results and implementation ratings, annual
  assessment goals and the payment summary.

  Access: the school is loaded as the signed-in user inside their tenant, so
  a school they cannot read redirects with "not found". Updates are offered
  only to contributors and org admins, and every save is re-authorized by the
  resource policies, so a forged event from a viewer is refused.
  """
  use EmisintWeb, :live_view

  import EmisintWeb.Improvement.Components
  import EmisintWeb.Improvement.StateResultsComponents

  alias Emisint.Improvement.{Access, Dashboard, EntryForm, Percent, Rubric}
  alias Emisint.NdInsights.SchoolResults

  @state_params ~w(state_year state_type state_subgroup)

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.scope

    with {:ok, school} <- Dashboard.fetch_school(scope, slug),
         {:ok, defs} <- Dashboard.load_plan(scope, school) do
      {:ok,
       assign(socket,
         page_title: school.name,
         school: school,
         defs: defs,
         can_contribute?:
           Access.can_contribute?(scope.current_user, scope.current_tenant, school),
         editing: nil,
         state: load_state(scope, school)
       )}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "That school was not found, or you don't have access to it.")
         |> push_navigate(to: ~p"/school-goals")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    %{defs: defs, school: school, scope: scope} = socket.assigns

    period =
      Enum.find(defs.periods, &(&1.code == params["period"])) ||
        Dashboard.default_period(scope, school, defs.periods)

    socket =
      socket
      |> assign(period: period, params: Map.take(params, ["period" | @state_params]))
      |> load_period()
      |> assign_state_filters(params)
      |> assign(editing: nil)

    {:noreply, maybe_open_from_params(socket, params["update"])}
  end

  # Official state results are annual and have their own year selector; they
  # are never tied to the seasonal reporting period above.
  defp load_state(scope, %{state: "ND", state_entity_id: id}) when is_binary(id),
    do: SchoolResults.load(scope.current_user, id)

  defp load_state(_scope, _school), do: SchoolResults.load(nil, nil)

  defp assign_state_filters(socket, params) do
    %{years: years, rows: rows} = socket.assigns.state
    year = if params["state_year"] in years, do: params["state_year"], else: List.first(years)
    types = Enum.map(SchoolResults.assessment_types(), &elem(&1, 0))
    type = if params["state_type"] in types, do: params["state_type"], else: "Comp"
    subgroups = SchoolResults.subgroups(rows, year)
    subgroup = if params["state_subgroup"] in subgroups, do: params["state_subgroup"], else: "All"

    assign(socket,
      state_filters: %{year: year, type: type, subgroup: subgroup, subgroups: subgroups}
    )
  end

  defp patch_with(socket, changes) do
    query =
      socket.assigns.params |> Map.merge(changes) |> Enum.reject(fn {_, v} -> v in [nil, ""] end)

    push_patch(socket, to: ~p"/school-goals/#{socket.assigns.school.slug}?#{query}")
  end

  defp maybe_open_from_params(socket, nil), do: socket

  defp maybe_open_from_params(socket, code) do
    case Enum.find(socket.assigns.defs.metrics, &(&1.code == code)) do
      nil -> socket
      metric -> open_editor(socket, metric)
    end
  end

  defp load_period(socket) do
    %{scope: scope, school: school, period: period, defs: defs} = socket.assigns
    data = Dashboard.load_period(scope, school, period)

    assign(socket,
      data: data,
      averages: Dashboard.seasonal_averages(defs.metrics, data.ratings)
    )
  end

  @impl true
  def handle_event("select_period", %{"period" => code}, socket) do
    {:noreply, patch_with(socket, %{"period" => code})}
  end

  def handle_event("state_filters", params, socket) do
    {:noreply, patch_with(socket, Map.take(params, @state_params))}
  end

  def handle_event("open_update", %{"metric-id" => metric_id}, socket) do
    case Enum.find(socket.assigns.defs.metrics, &(&1.id == metric_id)) do
      nil -> {:noreply, socket}
      metric -> {:noreply, open_editor(socket, metric)}
    end
  end

  def handle_event("close_update", _params, socket) do
    {:noreply, assign(socket, editing: nil)}
  end

  def handle_event("change_actual", %{"actual" => params}, socket) do
    {:noreply, update_form(socket, :actual_form, params, :actual)}
  end

  def handle_event("change_rating", %{"rating" => params}, socket) do
    {:noreply, update_form(socket, :rating_form, params, :rating)}
  end

  def handle_event("save_actual", %{"actual" => params}, socket) do
    save(socket, :actual, params)
  end

  def handle_event("save_rating", %{"rating" => params}, socket) do
    save(socket, :rating, params)
  end

  defp open_editor(socket, metric) do
    if socket.assigns.can_contribute? do
      %{data: data} = socket.assigns
      actual = data.actuals[metric.id]
      rating = data.ratings[metric.id]

      assign(socket,
        editing: %{
          metric: metric,
          actual: actual,
          rating: rating,
          actual_form: to_form(actual_params(actual, metric), as: :actual),
          rating_form: to_form(rating_params(rating), as: :rating)
        }
      )
    else
      put_flash(socket, :error, "You have read-only access to this school.")
    end
  end

  defp update_form(%{assigns: %{editing: %{} = editing}} = socket, key, params, as) do
    assign(socket, editing: Map.put(editing, key, to_form(params, as: as)))
  end

  defp update_form(socket, _key, _params, _as), do: socket

  defp save(%{assigns: %{can_contribute?: false}} = socket, _kind, _params) do
    {:noreply, put_flash(socket, :error, "You have read-only access to this school.")}
  end

  defp save(%{assigns: %{editing: nil}} = socket, _kind, _params), do: {:noreply, socket}

  defp save(socket, kind, params) do
    %{scope: scope, period: period, editing: editing} = socket.assigns

    result =
      case kind do
        :actual -> EntryForm.submit_actual(scope, editing.metric, period, editing.actual, params)
        :rating -> EntryForm.submit_rating(scope, editing.metric, period, editing.rating, params)
      end

    case result do
      {:ok, _entry} ->
        socket = load_period(socket)
        metric = editing.metric

        {:noreply,
         socket
         |> open_editor(metric)
         |> put_flash(:info, saved_message(kind, editing))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to update this school.")}

      {:error, errors} ->
        {form_key, as} =
          if kind == :actual, do: {:actual_form, :actual}, else: {:rating_form, :rating}

        form = to_form(params, as: as, errors: Enum.map(errors, fn {f, m} -> {f, {m, []}} end))
        {:noreply, assign(socket, editing: Map.put(editing, form_key, form))}
    end
  end

  defp saved_message(:actual, %{actual: nil}), do: "Actual result saved."

  defp saved_message(:actual, _),
    do: "Actual result corrected. The original entry is kept in the history."

  defp saved_message(:rating, %{rating: nil}), do: "Implementation rating saved."

  defp saved_message(:rating, _),
    do: "Implementation rating corrected. The original entry is kept in the history."

  defp actual_params(nil, _metric), do: %{"value_state" => "exact", "evidence" => %{}}

  defp actual_params(entry, metric) do
    %{
      "value_state" => to_string(entry.value_state),
      "value" => input_number(metric, entry.value),
      "range_low" => input_number(metric, entry.range_low),
      "range_high" => input_number(metric, entry.range_high),
      "suppression_reason" => entry.suppression_reason,
      "measurement_date" => entry.measurement_date && Date.to_iso8601(entry.measurement_date),
      "notes" => entry.notes,
      "evidence" => evidence_params(entry.evidence_links)
    }
  end

  defp rating_params(nil), do: %{"rating_state" => "rated", "evidence" => %{}}

  defp rating_params(entry) do
    %{
      "rating_state" => to_string(entry.rating_state),
      "score" => entry.score && Integer.to_string(entry.score),
      "measurement_date" => entry.measurement_date && Date.to_iso8601(entry.measurement_date),
      "notes" => entry.notes,
      "evidence" => evidence_params(entry.evidence_links)
    }
  end

  defp input_number(%{unit: :percent}, value), do: Percent.number(value)
  defp input_number(_metric, nil), do: nil
  defp input_number(_metric, value), do: Decimal.to_string(value, :normal)

  defp evidence_params(links) do
    links
    |> Enum.with_index()
    |> Map.new(fn {link, i} ->
      {Integer.to_string(i), %{"url" => link.url, "label" => link.label}}
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="p-4 md:p-6 max-w-7xl mx-auto space-y-6">
        <div>
          <.link
            navigate={~p"/school-goals"}
            class="text-sm text-base-content/50 hover:text-base-content flex items-center gap-1 mb-3"
          >
            <.icon name="hero-arrow-left" class="size-4" /> School Goals
          </.link>
          <div class="flex flex-col md:flex-row md:items-end md:justify-between gap-4">
            <div>
              <h1 class="text-2xl font-bold">{@school.name}</h1>
              <div class="flex flex-wrap items-center gap-2 mt-1 text-sm text-base-content/60">
                <span>{@school.district_name}</span>
                <span :if={@school.grade_span}>· Grades {@school.grade_span}</span>
                <span class="font-mono">· {@school.state} {@school.state_entity_id}</span>
                <span class="badge badge-ghost badge-sm">{@defs.plan.name}</span>
                <span
                  :if={!@can_contribute?}
                  class="badge badge-outline badge-sm"
                  id="read-only-badge"
                >
                  Read-only
                </span>
              </div>
            </div>

            <form phx-change="select_period" id="period-select" class="form-control">
              <label class="label py-1" for="period">
                <span class="label-text text-xs uppercase tracking-wide">Reporting period</span>
              </label>
              <select name="period" id="period" class="select select-bordered select-sm w-48">
                <option :for={p <- @defs.periods} value={p.code} selected={p.id == @period.id}>
                  {p.label}
                </option>
              </select>
            </form>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div
            :for={category <- [:systems, :student_outcome]}
            class="bg-base-100 border border-base-200 rounded-xl p-4"
            id={"seasonal-average-#{category}"}
          >
            <div class="text-xs uppercase tracking-wide text-base-content/60">
              {category_label(category)} · {@period.label} implementation
            </div>
            <div class="text-2xl font-bold mt-1">
              <span :if={@averages[category].average}>{@averages[category].average}</span>
              <span :if={!@averages[category].average} class="text-base-content/40 text-lg">
                Not rated
              </span>
              <span class="text-sm font-normal text-base-content/50">/ {@defs.plan.max_rating}</span>
            </div>
            <div class="text-xs text-base-content/50 mt-1">
              {@averages[category].rated} of {@averages[category].total} metrics rated.
              Seasonal ratings are progress checks, not payment inputs.
            </div>
          </div>

          <div class="bg-base-100 border border-base-200 rounded-xl p-4" id="payment-card">
            <div class="text-xs uppercase tracking-wide text-base-content/60">
              Performance-based payment
            </div>
            <div class="text-2xl font-bold mt-1">Awaiting review</div>
            <div class="text-xs text-base-content/50 mt-1 space-y-0.5">
              <div>
                Calculated only from formal 18-month review ratings, which have not been recorded.
                Seasonal ratings never produce a payment amount.
              </div>
              <div>
                Up to {format_money(@defs.payment.payment_cap)} · Systems {format_weight(
                  @defs.payment.systems_weight
                )} ({@defs.payment.systems_metric_count} metrics) · Student Outcome {format_weight(
                  @defs.payment.outcomes_weight
                )} ({@defs.payment.outcomes_metric_count} metrics)
              </div>
            </div>
          </div>
        </div>

        <nav
          id="page-nav"
          aria-label="Page sections"
          class="flex flex-wrap items-center gap-1 border-b border-base-200 pb-2"
        >
          <span class="text-xs uppercase tracking-wide text-base-content/50 mr-1">Jump to</span>
          <a href="#goals" class="btn btn-xs btn-ghost">Goals</a>
          <a href="#annual-goals" class="btn btn-xs btn-ghost">Annual Targets</a>
          <a href="#state-results" class="btn btn-xs btn-ghost">State Results</a>
        </nav>

        <div id="goals" class="space-y-6 scroll-mt-4">
          <section
            :for={goal <- @defs.goals}
            class="bg-base-100 border border-base-200 rounded-xl overflow-hidden"
            id={"goal-#{goal.number}"}
          >
            <div class="px-4 py-3 border-b border-base-200">
              <h2 class="font-semibold">Goal {goal.number}: {goal.title}</h2>
              <p :if={goal.description} class="text-sm text-base-content/60 mt-1">
                {goal.description}
              </p>
              <.review_column_note goal={goal} metrics={Map.get(@defs.metrics_by_goal, goal.id, [])} />
              <.implementation_steps
                :if={goal.implementation_steps != %{}}
                goal={goal}
                period={@period}
                periods={@defs.periods}
                plan={@defs.plan}
              />
            </div>

            <div class="overflow-x-auto">
              <table class="table table-sm w-full table-fixed min-w-[52rem]">
                <colgroup>
                  <col class="w-[29%]" />
                  <col class="w-[18%]" />
                  <col class="w-[21%]" />
                  <col class="w-[22%]" />
                  <col class="w-24" />
                </colgroup>
                <thead>
                  <tr class="bg-base-200/60 text-base-content/70 text-xs uppercase tracking-wide align-bottom">
                    <th class="whitespace-normal">Metric</th>
                    <th class="whitespace-normal">Baseline &amp; targets</th>
                    <th class="border-l border-base-200 whitespace-normal">
                      Actual result
                      <span class="block normal-case tracking-normal">{@period.label}</span>
                    </th>
                    <th class="border-l border-base-200 whitespace-normal">
                      Implementation rating (0–3)
                      <span class="block normal-case tracking-normal">{@period.label}</span>
                    </th>
                    <th class="sticky right-0 bg-base-200 z-10">
                      <span class="sr-only">Actions</span>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={metric <- Map.get(@defs.metrics_by_goal, goal.id, [])}
                    id={"metric-#{metric.code}"}
                    class="align-top"
                  >
                    <td>
                      <div class="font-mono text-xs text-base-content/50">{metric.code}</div>
                      <div class="font-medium break-words">{metric.description}</div>
                      <div class="flex flex-wrap gap-1 mt-1">
                        <span class="badge badge-outline badge-xs">
                          {category_label(metric.category)}
                        </span>
                        <span
                          :if={metric.direction == :lower_is_better}
                          class="badge badge-outline badge-xs"
                        >
                          Lower is better
                        </span>
                      </div>
                    </td>
                    <td>
                      <dl class="grid grid-cols-[auto_1fr] items-baseline gap-x-2 gap-y-0.5 text-xs">
                        <dt class="text-base-content/50">Baseline</dt>
                        <dd><.target metric={metric} field={:baseline_value} /></dd>
                        <dt class="text-base-content/50">18-mo</dt>
                        <dd><.target metric={metric} field={:target_18m} /></dd>
                        <dt class="text-base-content/50">36-mo</dt>
                        <dd><.target metric={metric} field={:target_36m} /></dd>
                      </dl>
                      <.target_source_details metric={metric} class="mt-1" />
                    </td>
                    <td class="border-l border-base-200 break-words" id={"actual-#{metric.code}"}>
                      <.actual_value entry={@data.actuals[metric.id]} metric={metric} />
                      <.compact_provenance
                        :if={@data.actuals[metric.id]}
                        id={"actual-source-#{metric.code}"}
                        entry={@data.actuals[metric.id]}
                        users={@data.users}
                      />
                    </td>
                    <td class="border-l border-base-200 break-words" id={"rating-#{metric.code}"}>
                      <.rating_value entry={@data.ratings[metric.id]} />
                      <.compact_provenance
                        :if={@data.ratings[metric.id]}
                        id={"rating-source-#{metric.code}"}
                        entry={@data.ratings[metric.id]}
                        users={@data.users}
                      />
                    </td>
                    <td class="sticky right-0 bg-base-100 z-10 border-l border-base-200">
                      <div class="flex flex-col items-stretch gap-1">
                        <button
                          :if={@can_contribute?}
                          class="btn btn-xs btn-primary"
                          phx-click="open_update"
                          phx-value-metric-id={metric.id}
                          id={"update-#{metric.code}"}
                        >
                          Update
                        </button>
                        <.link
                          navigate={~p"/school-goals/#{@school.slug}/metrics/#{metric.code}"}
                          class="btn btn-xs btn-ghost"
                          id={"history-#{metric.code}"}
                        >
                          History
                        </.link>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>

        <section
          class="bg-base-100 border border-base-200 rounded-xl overflow-hidden scroll-mt-4"
          id="annual-goals"
        >
          <div class="px-4 py-3 border-b border-base-200">
            <h2 class="font-semibold">Annual state assessment goals</h2>
            <p class="text-sm text-base-content/60 mt-1">
              Percentage of tested students scoring <strong>Proficient or Advanced</strong>
              on the state assessment, including the alternate assessment. This is a different
              measure from the workbook's “Proficient” metrics above. A published result is
              shown only for the same school year, all grades, all students and the combined
              assessment.
            </p>
          </div>
          <div class="overflow-x-auto">
            <table class="table table-sm w-full">
              <thead>
                <tr class="bg-base-200/60 text-base-content/70 text-xs uppercase tracking-wide align-bottom">
                  <th>School year</th>
                  <th class="whitespace-normal">ELA goal</th>
                  <th class="whitespace-normal">ELA published · Proficient or Advanced (derived)</th>
                  <th class="whitespace-normal border-l border-base-200">Math goal</th>
                  <th class="whitespace-normal">Math published · Proficient or Advanced (derived)</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{year, goals} <- annual_rows(@defs.annual_goals)} id={"annual-#{year}"}>
                  <td class="font-medium">{year}</td>
                  <td>{goals[:ela] && Percent.format(goals[:ela].target_value)}</td>
                  <td id={"annual-#{year}-ela"}>
                    <.goal_comparison
                      :if={goals[:ela]}
                      comparison={SchoolResults.compare_goal(goals[:ela], @state.rows)}
                    />
                  </td>
                  <td class="border-l border-base-200">
                    {goals[:math] && Percent.format(goals[:math].target_value)}
                  </td>
                  <td id={"annual-#{year}-math"}>
                    <.goal_comparison
                      :if={goals[:math]}
                      comparison={SchoolResults.compare_goal(goals[:math], @state.rows)}
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <.state_results
          school={@school}
          state={@state}
          filters={@state_filters}
          annual_goal_years={@defs.annual_goals |> Enum.map(& &1.school_year) |> Enum.uniq()}
        />
      </div>

      <.update_panel
        :if={@editing}
        editing={@editing}
        period={@period}
        data={@data}
      />
    </Layouts.app>
    """
  end

  # One explanation per goal instead of a badge on every metric. The metrics
  # keep their `:review_18m_column_heading_unconfirmed` flag.
  attr :goal, :map, required: true
  attr :metrics, :list, required: true

  defp review_column_note(assigns) do
    flagged = Enum.filter(assigns.metrics, &(:review_18m_column_heading_unconfirmed in &1.flags))

    assigns =
      assign(assigns, flagged: flagged, id: "review-column-note-goal-#{assigns.goal.number}")

    ~H"""
    <div :if={@flagged != []} class="mt-2">
      <button
        type="button"
        class="btn btn-xs btn-ghost gap-1 px-1 font-normal text-base-content/70"
        phx-click={
          JS.toggle(to: "##{@id}")
          |> JS.toggle_class("rotate-90", to: "##{@id}-chevron")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
        }
        aria-expanded="false"
        aria-controls={@id}
        id={"#{@id}-toggle"}
      >
        <span id={"#{@id}-chevron"} class="inline-flex transition-transform">
          <.icon name="hero-chevron-right-mini" class="size-4" />
        </span>
        18-month review column needs confirmation
      </button>
      <div
        id={@id}
        class="hidden mt-2 rounded-lg bg-base-200/50 p-3 text-sm text-base-content/70 space-y-1"
      >
        <p>
          In the goal workbook, this goal's 18-month column is headed “Target Check”
          (<span class="font-mono text-xs">Ft Yates Goals!I26</span>), while Goals 1–3 use
          “18-Month Review Rating” (<span class="font-mono text-xs">I3</span>, <span class="font-mono text-xs">I12</span>, <span class="font-mono text-xs">I19</span>).
        </p>
        <p>
          The payment sheet averages all of column I by category
          (<span class="font-mono text-xs">Performance-Based Payment!C4</span> and <span class="font-mono text-xs">E4</span>), so values entered there for {Enum.map_join(
            @flagged,
            ", ",
            & &1.code
          )} would count toward payment.
        </p>
        <p>
          Please confirm whether this column holds 18-month review ratings. Review ratings are
          not recorded in Emisint yet, and the payment remains “Awaiting review”.
        </p>
      </div>
    </div>
    """
  end

  # The workbook records only how many implementation steps are planned per
  # period (`Ft Yates Goals!C1`); their wording lives in the school's
  # action-planning document. Step text is never invented here.
  attr :goal, :map, required: true
  attr :period, :map, required: true
  attr :periods, :list, required: true
  attr :plan, :map, required: true

  defp implementation_steps(assigns) do
    assigns =
      assign(assigns,
        id: "steps-goal-#{assigns.goal.number}",
        count: assigns.goal.implementation_steps[assigns.period.code],
        planned: Enum.filter(assigns.periods, &assigns.goal.implementation_steps[&1.code])
      )

    ~H"""
    <div class="mt-2">
      <button
        type="button"
        class="btn btn-xs btn-ghost gap-1 px-1"
        phx-click={
          JS.toggle(to: "##{@id}")
          |> JS.toggle_class("rotate-90", to: "##{@id}-chevron")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
        }
        aria-expanded="false"
        aria-controls={@id}
        id={"#{@id}-toggle"}
      >
        <span id={"#{@id}-chevron"} class="inline-flex transition-transform">
          <.icon name="hero-chevron-right-mini" class="size-4" />
        </span>
        <span :if={@count}>{@count} planned implementation steps in {@period.label}</span>
        <span :if={!@count}>No implementation steps recorded for {@period.label}</span>
      </button>

      <div id={@id} class="hidden mt-2 rounded-lg bg-base-200/50 p-3 text-sm space-y-2">
        <p class="text-base-content/70">
          The goal workbook records how many actions are planned for each period, not their
          wording. The steps themselves are kept in the school's action-planning and
          progress-monitoring document.
        </p>
        <p :if={@plan.progress_doc_url}>
          <a
            href={@plan.progress_doc_url}
            target="_blank"
            rel="noopener noreferrer"
            class="link link-primary"
          >
            Open the action-planning document
          </a>
        </p>
        <p :if={!@plan.progress_doc_url} class="text-base-content/60" id={"#{@id}-no-doc"}>
          That document has not been linked yet (the workbook's link cell reads “TBD”).
        </p>
        <div>
          <div class="text-xs uppercase tracking-wide text-base-content/50 mb-1">
            Planned steps by period
          </div>
          <ul class="flex flex-wrap gap-1">
            <li
              :for={p <- @planned}
              class={[
                "badge badge-sm",
                if(p.id == @period.id, do: "badge-primary", else: "badge-ghost")
              ]}
            >
              {p.label}: {@goal.implementation_steps[p.code]}
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  attr :editing, :map, required: true
  attr :period, :map, required: true
  attr :data, :map, required: true

  defp update_panel(assigns) do
    ~H"""
    <div class="modal modal-open" id="update-panel" phx-window-keydown="close_update" phx-key="Escape">
      <div class="modal-box max-w-5xl">
        <div class="flex items-start justify-between gap-4 mb-4">
          <div>
            <div class="font-mono text-xs text-base-content/50">
              {@editing.metric.code} · {@period.label}
            </div>
            <h3 class="font-bold text-lg">{@editing.metric.description}</h3>
            <p class="text-sm text-base-content/60">
              The actual result and the implementation rating are saved separately; saving one
              never changes the other. Your name and the time are recorded automatically.
            </p>
          </div>
          <button class="btn btn-sm btn-ghost" phx-click="close_update" aria-label="Close">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <.form
            for={@editing.actual_form}
            id="actual-form"
            phx-change="change_actual"
            phx-submit="save_actual"
            class="space-y-3"
          >
            <h4 class="font-semibold">Actual result</h4>
            <.current_notice entry={@editing.actual} users={@data.users}>
              <:value><.actual_value entry={@editing.actual} metric={@editing.metric} /></:value>
            </.current_notice>
            <.base_errors form={@editing.actual_form} />

            <.select_field
              form={@editing.actual_form}
              field={:value_state}
              label="Result type"
              options={[
                {"Exact value", "exact"},
                {"Range", "range"},
                {"Suppressed by the source", "suppressed"},
                {"Unavailable (explain in notes)", "unavailable"}
              ]}
            />

            <.text_field
              :if={state(@editing.actual_form, :value_state) == "exact"}
              form={@editing.actual_form}
              field={:value}
              label={value_label(@editing.metric)}
              inputmode="decimal"
            />
            <div
              :if={state(@editing.actual_form, :value_state) == "range"}
              class="grid grid-cols-2 gap-3"
            >
              <.text_field
                form={@editing.actual_form}
                field={:range_low}
                label={"From #{unit_hint(@editing.metric)}"}
                inputmode="decimal"
              />
              <.text_field
                form={@editing.actual_form}
                field={:range_high}
                label={"To #{unit_hint(@editing.metric)}"}
                inputmode="decimal"
              />
            </div>
            <.text_field
              :if={state(@editing.actual_form, :value_state) == "suppressed"}
              form={@editing.actual_form}
              field={:suppression_reason}
              label="Reason stated by the source (optional, copied verbatim)"
            />
            <.text_field
              form={@editing.actual_form}
              field={:measurement_date}
              label={date_label(@editing.actual_form)}
              type="date"
            />
            <.textarea_field
              form={@editing.actual_form}
              field={:notes}
              label={notes_label(@editing.actual_form, :value_state)}
            />
            <.evidence_fields form={@editing.actual_form} />
            <.textarea_field
              :if={@editing.actual}
              form={@editing.actual_form}
              field={:correction_reason}
              label="Reason for correction (required)"
            />
            <button type="submit" class="btn btn-primary btn-sm">
              {if @editing.actual, do: "Save correction", else: "Save actual result"}
            </button>
          </.form>

          <.form
            for={@editing.rating_form}
            id="rating-form"
            phx-change="change_rating"
            phx-submit="save_rating"
            class="space-y-3 lg:border-l lg:border-base-200 lg:pl-6"
          >
            <h4 class="font-semibold">Implementation rating (0–3)</h4>
            <.current_notice entry={@editing.rating} users={@data.users}>
              <:value><.rating_value entry={@editing.rating} /></:value>
            </.current_notice>
            <.base_errors form={@editing.rating_form} />

            <.select_field
              form={@editing.rating_form}
              field={:rating_state}
              label="Rating"
              options={[
                {"Rated", "rated"},
                {"Not applicable", "not_applicable"},
                {"Unavailable (explain in notes)", "unavailable"}
              ]}
            />
            <.select_field
              :if={state(@editing.rating_form, :rating_state) == "rated"}
              form={@editing.rating_form}
              field={:score}
              label="Score"
              options={[
                {"Select a score", ""}
                | Enum.map(Rubric.levels(), fn {s, l, _} -> {"#{s} — #{l}", Integer.to_string(s)} end)
              ]}
            />
            <ul class="text-xs text-base-content/60 space-y-0.5">
              <li :for={{score, label, description} <- Rubric.levels()}>
                <strong>{score} — {label}:</strong> {description}
              </li>
            </ul>
            <.text_field
              form={@editing.rating_form}
              field={:measurement_date}
              label="Rating date (optional)"
              type="date"
            />
            <.textarea_field
              form={@editing.rating_form}
              field={:notes}
              label={notes_label(@editing.rating_form, :rating_state)}
            />
            <.evidence_fields form={@editing.rating_form} />
            <.textarea_field
              :if={@editing.rating}
              form={@editing.rating_form}
              field={:correction_reason}
              label="Reason for correction (required)"
            />
            <button type="submit" class="btn btn-primary btn-sm">
              {if @editing.rating, do: "Save correction", else: "Save rating"}
            </button>
          </.form>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="close_update"></div>
    </div>
    """
  end

  attr :entry, :any, required: true
  attr :users, :map, required: true
  slot :value, required: true

  defp current_notice(assigns) do
    ~H"""
    <div :if={@entry} class="alert alert-info text-sm py-2 block">
      <div>Current value: {render_slot(@value)}</div>
      <.provenance entry={@entry} users={@users} />
      <div class="mt-1">
        Saving creates a correction of this entry. The original stays in the history.
      </div>
    </div>
    """
  end

  attr :form, :any, required: true

  defp base_errors(assigns) do
    ~H"""
    <div :if={messages(@form, :base) != []} class="alert alert-error text-sm py-2" role="alert">
      <div :for={message <- messages(@form, :base)}>{message}</div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :inputmode, :string, default: nil

  defp text_field(assigns) do
    ~H"""
    <div class="form-control">
      <label class="label py-1" for={@form[@field].id}>
        <span class="label-text">{@label}</span>
      </label>
      <input
        type={@type}
        name={@form[@field].name}
        id={@form[@field].id}
        value={@form[@field].value}
        inputmode={@inputmode}
        class={[
          "input input-bordered input-sm w-full",
          messages(@form, @field) != [] && "input-error"
        ]}
      />
      <.field_errors form={@form} field={@field} />
    </div>
    """
  end

  attr :form, :any, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true

  defp textarea_field(assigns) do
    ~H"""
    <div class="form-control">
      <label class="label py-1" for={@form[@field].id}>
        <span class="label-text">{@label}</span>
      </label>
      <textarea
        name={@form[@field].name}
        id={@form[@field].id}
        rows="2"
        class={[
          "textarea textarea-bordered textarea-sm w-full",
          messages(@form, @field) != [] && "textarea-error"
        ]}
      >{@form[@field].value}</textarea>
      <.field_errors form={@form} field={@field} />
    </div>
    """
  end

  attr :form, :any, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true
  attr :options, :list, required: true

  defp select_field(assigns) do
    ~H"""
    <div class="form-control">
      <label class="label py-1" for={@form[@field].id}>
        <span class="label-text">{@label}</span>
      </label>
      <select
        name={@form[@field].name}
        id={@form[@field].id}
        class={[
          "select select-bordered select-sm w-full",
          messages(@form, @field) != [] && "select-error"
        ]}
      >
        <option
          :for={{label, value} <- @options}
          value={value}
          selected={to_string(@form[@field].value) == value}
        >
          {label}
        </option>
      </select>
      <.field_errors form={@form} field={@field} />
    </div>
    """
  end

  attr :form, :any, required: true

  defp evidence_fields(assigns) do
    ~H"""
    <fieldset class="space-y-2">
      <legend class="label-text">Evidence links (optional, http or https)</legend>
      <div :for={i <- 0..(EntryForm.max_evidence_links() - 1)} class="grid grid-cols-3 gap-2">
        <input
          type="url"
          name={"#{@form.name}[evidence][#{i}][url]"}
          value={evidence_value(@form, i, "url")}
          placeholder="https://…"
          class="input input-bordered input-sm col-span-2"
          aria-label={"Evidence link #{i + 1} URL"}
        />
        <input
          type="text"
          name={"#{@form.name}[evidence][#{i}][label]"}
          value={evidence_value(@form, i, "label")}
          placeholder="Label"
          class="input input-bordered input-sm"
          aria-label={"Evidence link #{i + 1} label"}
        />
      </div>
      <.field_errors form={@form} field={:evidence} />
    </fieldset>
    """
  end

  attr :form, :any, required: true
  attr :field, :atom, required: true

  defp field_errors(assigns) do
    ~H"""
    <p :for={message <- messages(@form, @field)} class="text-error text-xs mt-1">{message}</p>
    """
  end

  defp messages(form, field) do
    for {^field, {message, _}} <- form.errors, do: message
  end

  defp state(form, field), do: to_string(form[field].value)

  defp evidence_value(form, i, key) do
    get_in(form.params, ["evidence", Integer.to_string(i), key])
  end

  defp value_label(%{unit: :percent}), do: "Value (%, 0–100)"
  defp value_label(_metric), do: "Value"

  defp unit_hint(%{unit: :percent}), do: "(%, 0–100)"
  defp unit_hint(_metric), do: ""

  defp date_label(form) do
    if state(form, :value_state) in ["exact", "range"],
      do: "Measurement date (required)",
      else: "Measurement date (optional)"
  end

  defp notes_label(form, field) do
    if state(form, field) == "unavailable",
      do: "Explanation (required)",
      else: "Notes (optional)"
  end

  defp annual_rows(goals) do
    goals
    |> Enum.group_by(& &1.school_year)
    |> Enum.sort_by(fn {year, _} -> year end)
    |> Enum.map(fn {year, list} -> {year, Map.new(list, &{&1.subject, &1})} end)
  end
end
