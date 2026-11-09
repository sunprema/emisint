defmodule EmisintWeb.Improvement.SchoolGoalsLive do
  @moduledoc """
  School goals dashboard (ND First pilot): goals, metrics, the selected
  reporting period's actual results and implementation ratings, annual
  assessment goals and the payment summary.

  The period selector lists the seasonal updates and the 18- and 36-month
  reviews. A seasonal period records actual results and seasonal ratings
  (progress checks, never payment inputs). A review period records actual
  results (compared with the target due then) and the formal review ratings,
  which are the only input to the estimated payment (`Improvement.Payment`).
  Org admins can record an estimate for a complete checkpoint; it keeps the
  assumptions used. No actual payment is recorded.

  Access: the school is loaded as the signed-in user inside their tenant, so
  a school they cannot read redirects with "not found". Updates are offered
  only to contributors and org admins, and every save is re-authorized by the
  resource policies, so a forged event from a viewer is refused.
  """
  use EmisintWeb, :live_view

  import EmisintWeb.Improvement.Components
  import EmisintWeb.Improvement.StateResultsComponents

  alias Emisint.Improvement.{
    Access,
    Dashboard,
    Display,
    EntryForm,
    GoalStatus,
    GrowthPercentile,
    Payment,
    Percent,
    ResultGoals,
    Rubric
  }

  alias Emisint.NdInsights.SchoolResults

  @state_params ~w(state_year state_type state_subgroup goal_ref)

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    scope = socket.assigns.scope

    with {:ok, school} <- Dashboard.fetch_school(scope, slug),
         {:ok, defs} <- Dashboard.load_plan(scope, school) do
      if connected?(socket),
        do: Phoenix.PubSub.subscribe(Emisint.PubSub, Emisint.NdInsights.Importer.topic(session))

      # Pilot records this user can read: navigation lists only these.
      readable = Emisint.Improvement.Pilot.readable_slugs(scope)

      {:ok,
       assign(socket,
         page_title: school.name,
         school: school,
         defs: defs,
         can_contribute?:
           Access.can_contribute?(scope.current_user, scope.current_tenant, school),
         can_record_estimate?:
           Access.can_record_estimate?(scope.current_user, scope.current_tenant),
         # Matches the importer's own check; the import page enforces it again.
         can_import?:
           match?(%{role: :system_admin}, scope.current_user) and
             Emisint.Improvement.Pilot.pilot?(school),
         editing: nil,
         comparison: ResultGoals.config(school),
         tabs: Emisint.Improvement.Pilot.tabs(readable),
         tab_slug: Emisint.Improvement.Pilot.tab_slug(school),
         participant_nav: Emisint.Improvement.Pilot.participant_nav(school, readable),
         participant_scope: participant_scope(readable, school),
         plan_targets: Emisint.Improvement.PlanTargets.for_school(school),
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

  # Where this record sits among the ND First participants
  # (`Seeds.Participant`): a district participant links to its buildings and a
  # building links to its participant. Only records this user can read are
  # linked; the others are listed by name.
  defp participant_scope(readable, school) do
    case Emisint.Improvement.Seeds.Participant.scope(school) do
      %{kind: :participant, buildings: buildings} = s ->
        %{s | buildings: Enum.map(buildings, &related(readable, &1))}

      %{kind: :building, participant: participant} = s ->
        %{s | participant: related(readable, participant)}

      other ->
        other
    end
  end

  defp related(readable, module) do
    %{name: name, slug: slug, state_entity_id: id} = module.school()

    %{
      name: name,
      slug: slug,
      institution_id: id,
      readable?: MapSet.member?(readable, slug)
    }
  end

  # Official state results are annual and have their own year selector; they
  # are never tied to the seasonal reporting period above.
  defp load_state(scope, %{state: "ND", state_entity_id: id}) when is_binary(id),
    do: SchoolResults.load(scope.current_user, id)

  defp load_state(_scope, _school), do: SchoolResults.load(nil, nil)

  defp assign_state_filters(socket, params) do
    filters = SchoolResults.resolve_filters(socket.assigns.state, params)

    socket
    |> assign(state_filters: filters)
    |> assign_benchmark(filters.year)
  end

  # The selected year's North Dakota benchmark rows, reloaded when the year
  # changes or an import arrives.
  defp assign_benchmark(%{assigns: %{benchmark: %{year: year}}} = socket, year), do: socket

  defp assign_benchmark(socket, year) do
    rows = SchoolResults.load_benchmark(socket.assigns.scope.current_user, year)
    assign(socket, benchmark: %{year: year, rows: rows})
  end

  # The PDF uses the same period and state filters as the screen.
  defp report_query(period, filters) do
    [
      period: period.code,
      state_year: filters.year,
      state_type: filters.type,
      state_subgroup: filters.subgroup,
      goal_ref: ResultGoals.reference_param(filters.reference)
    ]
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
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
  def handle_info({:nd_insights_imported, institution_ids}, socket) do
    %{school: school, scope: scope, params: params} = socket.assigns

    if school.state_entity_id in institution_ids or
         Emisint.NdInsights.Benchmark.state_id() in institution_ids do
      {:noreply,
       socket
       |> assign(state: load_state(scope, school), benchmark: nil)
       |> assign_state_filters(params)
       |> put_flash(:info, "Official state results were updated by a new import.")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_period", %{"period" => code}, socket) do
    {:noreply, patch_with(socket, %{"period" => code})}
  end

  def handle_event("record_estimate", %{"checkpoint" => checkpoint}, socket) do
    %{scope: scope, defs: defs, can_record_estimate?: allowed?} = socket.assigns
    period = Enum.find(defs.periods, &(to_string(&1.kind) == checkpoint))

    cond do
      not allowed? ->
        {:noreply, put_flash(socket, :error, "Only org admins can record a payment estimate.")}

      is_nil(period) ->
        {:noreply, put_flash(socket, :error, "That review period was not found.")}

      true ->
        Emisint.Improvement.PaymentEstimate
        |> Ash.Changeset.for_create(:record, %{reporting_period_id: period.id}, scope: scope)
        |> Ash.create()
        |> case do
          {:ok, estimate} ->
            {:noreply,
             socket
             |> reload_defs()
             |> put_flash(
               :info,
               "Estimate recorded for the #{period.label}: #{Payment.money(estimate.amount)} (provisional cap and split)."
             )}

          {:error, %Ash.Error.Forbidden{}} ->
            {:noreply,
             put_flash(socket, :error, "Only org admins can record a payment estimate.")}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, "Estimate not recorded: #{error_text(error)}")}
        end
    end
  end

  # A disabled student-group select (only "All" published) is not submitted;
  # its absence clears any earlier group from the URL instead of keeping it.
  def handle_event("state_filters", params, socket) do
    changes = Map.merge(%{"state_subgroup" => nil}, Map.take(params, @state_params))
    {:noreply, patch_with(socket, changes)}
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

  def handle_event("change_published", %{"published" => params}, socket) do
    {:noreply, update_form(socket, :published_form, params, :published)}
  end

  def handle_event("save_published", %{"published" => params}, socket) do
    save(socket, :published, params)
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
          review?: review?(socket.assigns.period),
          actual_form: to_form(actual_params(actual, metric), as: :actual),
          rating_form: to_form(rating_params(rating), as: :rating),
          published_form: to_form(%{"source_year" => ""}, as: :published)
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
        :actual ->
          EntryForm.submit_actual(scope, editing.metric, period, editing.actual, params)

        :rating ->
          EntryForm.submit_rating(scope, editing.metric, period, editing.rating, params)

        :published ->
          EntryForm.submit_published(scope, editing.metric, period, editing.actual, params)
      end

    case result do
      {:ok, _entry} ->
        socket = socket |> reload_defs() |> load_period()
        metric = editing.metric

        {:noreply,
         socket
         |> open_editor(metric)
         |> put_flash(:info, saved_message(kind, editing))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to update this school.")}

      {:error, errors} ->
        {form_key, as} = form_key(kind)

        form = to_form(params, as: as, errors: Enum.map(errors, fn {f, m} -> {f, {m, []}} end))
        {:noreply, assign(socket, editing: Map.put(editing, form_key, form))}
    end
  end

  defp reload_defs(%{assigns: %{scope: scope, school: school}} = socket) do
    {:ok, defs} = Dashboard.load_plan(scope, school)
    assign(socket, defs: defs)
  end

  defp form_key(:actual), do: {:actual_form, :actual}
  defp form_key(:rating), do: {:rating_form, :rating}
  defp form_key(:published), do: {:published_form, :published}

  defp saved_message(:published, %{actual: nil}),
    do: "Published value saved as the review result."

  defp saved_message(:published, _),
    do:
      "Review result corrected with the published value. The original entry is kept in the history."

  defp saved_message(:actual, %{actual: nil}), do: "Actual result saved."

  defp saved_message(:actual, _),
    do: "Actual result corrected. The original entry is kept in the history."

  defp saved_message(:rating, %{rating: nil, review?: true}), do: "Formal review rating saved."

  defp saved_message(:rating, %{review?: true}),
    do: "Formal review rating corrected. The original entry is kept in the history."

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
        <.school_tabs tabs={@tabs} current={@tab_slug} />
        <.participant_nav nav={@participant_nav} />
        <div>
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

            <div class="flex flex-wrap items-end gap-2 w-full md:w-auto">
              <form
                :if={@participant_scope.kind != :building}
                phx-change="select_period"
                id="period-select"
                class="form-control w-full sm:w-auto"
              >
                <label class="label py-1" for="period">
                  <span class="label-text text-xs uppercase tracking-wide">Reporting period</span>
                </label>
                <select
                  name="period"
                  id="period"
                  class="select select-bordered select-sm w-full sm:w-48"
                >
                  <option :for={p <- @defs.periods} value={p.code} selected={p.id == @period.id}>
                    {p.label}
                  </option>
                </select>
              </form>
              <a
                href={
                  ~p"/school-goals/#{@school.slug}/report.pdf?#{report_query(@period, @state_filters)}"
                }
                target="_blank"
                rel="noopener"
                class="btn btn-sm btn-outline"
                id="download-pdf"
              >
                <.icon name="hero-document-arrow-down" class="size-4" /> Export PDF
              </a>
            </div>
          </div>
        </div>

        <.participant_scope_note scope={@participant_scope} school={@school} />

        <div
          :if={@participant_scope.kind != :building}
          class="grid grid-cols-1 sm:grid-cols-3 gap-3 items-start"
        >
          <div
            :for={category <- [:systems, :student_outcome]}
            class="bg-base-100 border border-base-200 rounded-xl px-4 py-3"
            id={"seasonal-average-#{category}"}
          >
            <div class="text-xs uppercase tracking-wide text-base-content/60">
              {category_label(category)} · {@period.label} implementation
            </div>
            <div :if={review?(@period)}>
              <div class="font-semibold">
                {@averages[category].rated} of {@averages[category].total} scored
              </div>
              <div class="text-xs text-base-content/50">
                Formal review ratings: the payment input. Averages appear in the estimated
                payment once every rating is recorded.
              </div>
            </div>
            <div :if={!review?(@period)} class="flex items-baseline gap-2">
              <span class="text-xl font-bold">
                <span :if={@averages[category].average}>{@averages[category].average}</span>
                <span :if={!@averages[category].average} class="text-base-content/40 text-base">
                  No ratings yet
                </span>
                <span class="text-sm font-normal text-base-content/50">
                  / {@defs.plan.max_rating}
                </span>
              </span>
              <span class="text-xs text-base-content/50">
                {@averages[category].rated} of {@averages[category].total} rated
              </span>
            </div>
            <div :if={!review?(@period)} class="text-xs text-base-content/50">
              Progress check, not a payment input.
            </div>
          </div>

          <div class="bg-base-100 border border-base-200 rounded-xl px-4 py-3" id="payment-card">
            <div class="text-xs uppercase tracking-wide text-base-content/60">
              {@defs.payment.label}
            </div>
            <div class="font-semibold" id="payment-combined">
              {Payment.combined_text(@defs.payment.combined)}
            </div>
            <div class="text-xs text-base-content/50">
              {if @defs.payment.terms.configured?,
                do: "Provisional, not an actual payment.",
                else: "No payment terms are set for this school."}
              <a href="#payment" class="link">Details</a>
            </div>
          </div>
        </div>

        <nav
          id="page-nav"
          aria-label="Page sections"
          class="flex flex-wrap items-center gap-1 border-b border-base-200 pb-2"
        >
          <span class="text-xs uppercase tracking-wide text-base-content/50 mr-1">Jump to</span>
          <a :if={@participant_scope.kind != :building} href="#goals" class="btn btn-xs btn-ghost">
            Goals
          </a>
          <a href="#annual-goals" class="btn btn-xs btn-ghost">Annual Targets</a>
          <a href="#state-results" class="btn btn-xs btn-ghost">State Results</a>
          <a
            :if={@participant_scope.kind != :building}
            href="#payment"
            class="btn btn-xs btn-ghost"
          >
            Estimated Payment
          </a>
        </nav>

        <div :if={@participant_scope.kind != :building} id="goals" class="space-y-6 scroll-mt-4">
          <p class="text-xs text-base-content/70" id="status-legend">
            <span class="font-medium">Status:</span>
            <span class="nd-text-success font-medium">Meets target</span>
            · <span class="nd-text-error font-medium">Below target</span>
            — a result compared with its own target when that target is due (18-month target at the
            18-Month Review, 36-month target at the 36-Month Review), respecting whether the metric
            should rise or fall; reaching the target exactly counts as meeting it. Choose the
            18-Month Review or 36-Month Review in “Reporting period” to see or enter those results.
            Uncolored: not reported, no target due this period, or not comparable. Ratings use the 0–3 rubric: <span class="nd-text-success font-medium">3 · Demonstrated Progress</span>, <span class="nd-text-info font-medium">2 · Implementation on Track</span>, <span class="nd-text-warning font-medium">1 · Some Progress</span>, <span class="nd-text-error font-medium">0 · Not Started</span>.
          </p>
          <section
            :for={goal <- @defs.goals}
            class="bg-base-100 border border-base-200 rounded-xl overflow-hidden"
            id={"goal-#{goal.number}"}
          >
            <div class="px-4 py-3 border-b border-base-200">
              <h2 class="font-semibold">Goal {goal.number}: {goal.title}</h2>
              <p :if={goal.description} class="text-sm text-base-content/60 mt-1">
                {Display.goal_description(goal.description)}
              </p>
              <.review_column_note
                goal={goal}
                metrics={Map.get(@defs.metrics_by_goal, goal.id, [])}
                goals={@defs.goals}
                metrics_by_goal={@defs.metrics_by_goal}
              />
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
                        <span
                          :if={Display.unit_label(metric)}
                          class="badge badge-outline badge-xs"
                          id={"unit-#{metric.code}"}
                        >
                          {Display.unit_label(metric)}
                        </span>
                      </div>
                      <.insights_source metric={metric} rows={@state.rows} />
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
                      <.goal_result
                        status={GoalStatus.evaluate(metric, @data.actuals[metric.id], @period)}
                        id={"status-#{metric.code}"}
                      >
                        <.actual_value entry={@data.actuals[metric.id]} metric={metric} />
                      </.goal_result>
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
              on the state assessment, including the alternate assessment.<span :if={
                workbook_proficient_alone?(@comparison)
              }> This is a different
              measure from the workbook's “Proficient” metrics above.</span> A published result is
              shown only for the same school year, all grades, all students and the combined
              assessment.
            </p>
            <p
              :if={@comparison.annual_note}
              class="text-xs text-base-content/60 mt-1"
              id="annual-goal-period"
            >
              {@comparison.annual_note}
            </p>
            <.annual_year_mapping years={@comparison.annual_years} />
            <p
              :if={@participant_scope.kind == :participant}
              class="text-xs text-base-content/60 mt-1"
              id="annual-by-building"
            >
              Building dashboards:
              <.related_links schools={@participant_scope.buildings} id_prefix="annual-building" />
            </p>
            <p class="text-xs text-base-content/60 mt-1" id="annual-color-key">
              Compared with the same school year's published result by the same rule as the
              state results: green “Meets target” when the whole published value is at or above
              the target, red “Below target” when it is entirely below, amber “Range overlaps
              target” otherwise. A dashboard comparison, not an official rating.
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
                      match={ResultGoals.annual(goals[:ela], @state.rows, @comparison)}
                    />
                  </td>
                  <td class="border-l border-base-200">
                    {goals[:math] && Percent.format(goals[:math].target_value)}
                  </td>
                  <td id={"annual-#{year}-math"}>
                    <.goal_comparison
                      :if={goals[:math]}
                      match={ResultGoals.annual(goals[:math], @state.rows, @comparison)}
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <.plan_targets_section targets={@plan_targets} />

        <.state_results
          school={@school}
          state={@state}
          filters={@state_filters}
          benchmark_rows={@benchmark.rows}
          metrics={@defs.metrics}
          annual_goals={@defs.annual_goals}
          import_path={if @can_import?, do: ~p"/school-goals/#{@school.slug}/import"}
          comparison_pdf_path={
            ~p"/school-goals/#{@school.slug}/report.pdf?#{report_query(@period, @state_filters) ++ [nd_comparison: "1"]}"
          }
          link_params={
            Map.new(report_query(@period, @state_filters), fn {k, v} -> {to_string(k), v} end)
          }
        />

        <.payment_section
          :if={@participant_scope.kind != :building}
          payment={@defs.payment}
          estimates={@defs.payment_estimates}
          can_record?={@can_record_estimate?}
        />
      </div>

      <.update_panel
        :if={@editing}
        editing={@editing}
        period={@period}
        data={@data}
        state_rows={@state.rows}
      />
    </Layouts.app>
    """
  end

  # One explanation per goal instead of a badge on every metric. The metrics
  # keep their `:review_18m_column_heading_unconfirmed` flag.
  attr :goal, :map, required: true
  attr :metrics, :list, required: true
  attr :goals, :list, required: true
  attr :metrics_by_goal, :map, required: true

  defp review_column_note(assigns) do
    flagged = Enum.filter(assigns.metrics, &(:review_18m_column_heading_unconfirmed in &1.flags))
    heading = Emisint.Improvement.Workbook.review_heading(assigns.metrics)

    # Goals in the same plan whose 18-month column is headed "18-Month Review Rating".
    confirmed =
      for goal <- assigns.goals,
          metrics = Map.get(assigns.metrics_by_goal, goal.id, []),
          metrics != [],
          not Enum.any?(metrics, &(:review_18m_column_heading_unconfirmed in &1.flags)),
          h = Emisint.Improvement.Workbook.review_heading(metrics),
          h != nil,
          do: {goal.number, h.cell |> String.split("!") |> List.last()}

    payment_row = heading && Emisint.Improvement.Workbook.payment_row(heading.sheet)

    assigns =
      assign(assigns,
        flagged: flagged,
        heading: heading,
        confirmed: confirmed,
        payment_row: payment_row,
        id: "review-column-note-goal-#{assigns.goal.number}"
      )

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
          In the goal workbook, this goal's 18-month column is headed “{(@heading && @heading.raw) ||
            "Target Check"}”
          <span :if={@heading}>(<span class="font-mono text-xs">{@heading.cell}</span>)</span><span :if={
            @confirmed != []
          }>,
            while {Enum.map_join(@confirmed, ", ", fn {n, _} -> "Goal #{n}" end)} {if length(@confirmed) == 1, do: "uses", else: "use"} “18-Month Review Rating”
            ({Enum.map_join(@confirmed, ", ", fn {_, cell} -> cell end)})</span>.
        </p>
        <p>
          In the workbook's payment sheet, the payment is computed from the ratings in column I,
          averaged by category<span :if={@payment_row}>
            (<span class="font-mono text-xs">Performance-Based Payment!C{@payment_row}</span>
            and <span class="font-mono text-xs">E{@payment_row}</span>)</span>. Because it averages the
          whole column, any 0–3 rating entered in this column for {Enum.map_join(
            @flagged,
            ", ",
            & &1.code
          )} would be counted as a review rating. The targets and actual results shown here are
          not ratings and never produce a payment on their own.
        </p>
        <p>
          Still to confirm: whether this column holds 18-month review ratings for Goal 4. The
          provisional estimate follows the workbook formula, which averages every metric in the
          category, so it expects a formal review rating for each of {Enum.map_join(
            @flagged,
            ", ",
            & &1.code
          )} as well; it is not resolved here.
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
        <span :if={@count}>
          {@count} planned implementation {if @count == 1, do: "step", else: "steps"} in {@period.label}
        </span>
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

  # The ND Insights measure behind a growth-percentile metric, with the
  # latest published year as reference only (never a result for a period).
  attr :metric, :map, required: true
  attr :rows, :list, required: true

  defp insights_source(assigns) do
    assigns =
      assign(assigns,
        mapping: GrowthPercentile.mapping(assigns.metric),
        latest: assigns.rows |> GrowthPercentile.published(assigns.metric) |> List.first()
      )

    ~H"""
    <div
      :if={@mapping}
      class="text-xs text-base-content/60 mt-1 space-y-0.5"
      id={"insights-source-#{@metric.code}"}
    >
      <div>
        ND Insights source: Overall Growth Percentile · {@mapping["subject"]} · All Grades · All students
      </div>
      <div :if={@latest} id={"insights-latest-#{@metric.code}"}>
        Published {@latest.academic_year}: {published_text(@latest)} (reference only; not a result for this period)
      </div>
      <div :if={!@latest}>No published value imported.</div>
    </div>
    """
  end

  defp published_text(%{value_state: :exact, value: v}), do: Decimal.to_string(v, :normal)

  defp published_text(%{value_state: :range, range_low: l, range_high: h}),
    do: "#{Decimal.to_string(l, :normal)}–#{Decimal.to_string(h, :normal)} (range)"

  defp published_text(%{value_state: :suppressed}), do: "Suppressed"

  defp review?(period), do: GrowthPercentile.review_period?(period)

  # Fort Yates's workbook tracks "Proficient" alone, a different measure from
  # the annual Proficient-or-Advanced goals; Oberon's tracks Proficient &
  # Advanced.
  defp workbook_proficient_alone?(comparison),
    do: Enum.any?(comparison.workbook, &match?({_, _, :achievement, _, "Proficient", _}, &1))

  defp error_text(%{errors: errors}) when is_list(errors),
    do: Enum.map_join(errors, "; ", &Exception.message/1)

  defp error_text(error), do: Exception.message(error)

  attr :payment, :map, required: true
  attr :estimates, :list, required: true
  attr :can_record?, :boolean, required: true

  defp payment_section(assigns) do
    ~H"""
    <section
      class="bg-base-100 border border-base-200 rounded-xl overflow-hidden scroll-mt-4"
      id="payment"
    >
      <div class="px-4 py-3 border-b border-base-200 space-y-1">
        <h2 class="font-semibold">{@payment.label}</h2>
        <p class="text-sm text-base-content/70" id="payment-terms-summary">
          {Payment.terms_summary(@payment.terms)} Only formal 18- and 36-month review ratings count. Estimates are not actual payments.
        </p>
      </div>
      <div class="overflow-x-auto" tabindex="0" role="region" aria-label="Estimated payment table">
        <table class="table table-sm w-full" id="payment-checkpoints">
          <thead>
            <tr class="bg-base-200/60 text-base-content/70 text-xs uppercase tracking-wide align-bottom">
              <th>Checkpoint</th>
              <th class="whitespace-normal">Weights (Systems / Student Outcomes)</th>
              <th>Allocation</th>
              <th class="whitespace-normal">Estimated payment</th>
              <th :if={@can_record?}></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={c <- @payment.checkpoints} id={"payment-#{c.checkpoint}"}>
              <td class="font-medium">{c.label}</td>
              <td class="whitespace-nowrap">
                {format_weight(c.systems_weight)} / {format_weight(c.outcomes_weight)}
              </td>
              <td>{Payment.money(c.allocation)}</td>
              <td id={"payment-#{c.checkpoint}-estimate"}>
                <span :if={c.status == :estimated} class="font-semibold">
                  {Payment.status_text(c)}
                </span>
                <span :if={c.status != :estimated} class="text-base-content/70">
                  {Payment.status_text(c)}
                </span>
              </td>
              <td :if={@can_record?}>
                <button
                  :if={c.status == :estimated}
                  class="btn btn-xs"
                  phx-click="record_estimate"
                  phx-value-checkpoint={c.checkpoint}
                  id={"record-estimate-#{c.checkpoint}"}
                >
                  Record estimate
                </button>
              </td>
            </tr>
            <tr id="payment-combined-row" class="border-t-2 border-base-300">
              <td class="font-medium">Both checkpoints</td>
              <td colspan="2"></td>
              <td class="font-semibold" id="payment-combined-text">
                {Payment.combined_text(@payment.combined)}
              </td>
              <td :if={@can_record?}></td>
            </tr>
          </tbody>
        </table>
      </div>
      <details class="px-4 py-3 border-t border-base-200 text-sm" id="payment-details">
        <summary class="cursor-pointer font-medium">How the estimate is calculated</summary>
        <div class="mt-2 space-y-2">
          <p class="text-base-content/70" id="payment-terms">
            {Payment.terms_text(@payment.terms)}
          </p>
          <p class="text-xs text-base-content/60" id="payment-formula">
            Estimate = {@payment.formula}, capped at the checkpoint allocation and rounded to cents.
            Category averages are taken separately before the weights apply. Only formal
            18- and 36-month review ratings count: seasonal ratings, targets and actual results
            never do. Every metric needs a review rating (an explicit 0 counts); otherwise the
            checkpoint stays “Awaiting review”. Estimates are not actual payments.
          </p>
          <div
            class="overflow-x-auto"
            tabindex="0"
            role="region"
            aria-label="Estimated payment calculation"
          >
            <table class="table table-sm w-full" id="payment-calculation">
              <thead>
                <tr class="bg-base-200/60 text-base-content/70 text-xs uppercase tracking-wide align-bottom">
                  <th>Checkpoint</th>
                  <th class="whitespace-normal">
                    Systems average ({@payment.systems_metric_count} metrics)
                  </th>
                  <th class="whitespace-normal">
                    Student Outcome average ({@payment.outcomes_metric_count} metrics)
                  </th>
                  <th>Weights</th>
                  <th class="whitespace-normal">Weighted score (of {@payment.max_rating})</th>
                  <th>Allocation</th>
                  <th class="whitespace-normal">Estimated payment</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={c <- @payment.checkpoints} id={"payment-calc-#{c.checkpoint}"}>
                  <td class="font-medium">{c.label}</td>
                  <td>{Payment.score_text(c.systems_average)}</td>
                  <td>{Payment.score_text(c.outcomes_average)}</td>
                  <td class="whitespace-nowrap">
                    {format_weight(c.systems_weight)} / {format_weight(c.outcomes_weight)}
                  </td>
                  <td>{Payment.score_text(c.weighted_score)}</td>
                  <td>{Payment.money(c.allocation)}</td>
                  <td>{Payment.status_text(c)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </details>
      <div class="px-4 py-3 border-t border-base-200 text-sm" id="payment-estimates">
        <h3 class="font-semibold">Recorded estimates</h3>
        <p :if={@estimates == []} class="text-base-content/60">
          None recorded. Recorded estimates keep the cap, allocation, weights and ratings used, so a
          later change to the terms does not rewrite them.
        </p>
        <ul :if={@estimates != []} class="space-y-1 mt-1">
          <li :for={e <- @estimates} id={"payment-estimate-#{e.id}"}>
            <span class="font-medium">
              {checkpoint_label(e.checkpoint)}: {Payment.money(e.amount)}
            </span>
            <span class="text-xs text-base-content/60">
              · {e.label} · recorded {Calendar.strftime(e.recorded_at, "%b %-d, %Y")} · terms v{e.terms_version} ({e.terms_status}):
              cap {Payment.money(e.payment_cap)}, allocation {Payment.money(e.allocation)}, weights {format_weight(
                e.systems_weight
              )} / {format_weight(e.outcomes_weight)},
              averages {Payment.score_text(e.systems_average)} / {Payment.score_text(
                e.outcomes_average
              )}, weighted {Payment.score_text(e.weighted_score)}, {length(e.inputs)} ratings
            </span>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  defp checkpoint_label(:review_18m), do: "18-month review"
  defp checkpoint_label(:review_36m), do: "36-month review"

  attr :editing, :map, required: true
  attr :period, :map, required: true
  attr :data, :map, required: true
  attr :state_rows, :list, required: true

  defp update_panel(assigns) do
    published = GrowthPercentile.published(assigns.state_rows, assigns.editing.metric)

    assigns =
      assign(assigns,
        published?:
          review?(assigns.period) and GrowthPercentile.mapping(assigns.editing.metric) != nil,
        published: published,
        # Nothing is preselected: a year is used only once someone chooses it.
        chosen:
          Enum.find(
            published,
            &(&1.academic_year == assigns.editing.published_form[:source_year].value)
          )
      )

    ~H"""
    <div class="modal modal-open" id="update-panel" phx-window-keydown="close_update" phx-key="Escape">
      <div class="modal-box max-w-5xl">
        <div class="flex items-start justify-between gap-4 mb-4">
          <div>
            <div class="font-mono text-xs text-base-content/50">
              {@editing.metric.code} · {@period.label}
            </div>
            <h3 class="font-bold text-lg">{@editing.metric.description}</h3>
            <p :if={!review?(@period)} class="text-sm text-base-content/60">
              The actual result and the implementation rating are saved separately; saving one
              never changes the other. Your name and the time are recorded automatically.
            </p>
            <p :if={review?(@period)} class="text-sm text-base-content/60" id="review-entry-note">
              {@period.label}: the actual result (compared with the target due at this review) and
              the formal review rating are saved separately; saving one never changes the other.
              Only the formal review rating feeds the estimated payment. Your name and the time are
              recorded automatically.
            </p>
          </div>
          <button class="btn btn-sm btn-ghost" phx-click="close_update" aria-label="Close">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div class="space-y-6">
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
          </div>

          <.form
            :if={@published?}
            for={@editing.published_form}
            id="published-form"
            phx-change="change_published"
            phx-submit="save_published"
            class="space-y-3 lg:border-l lg:border-base-200 lg:pl-6"
          >
            <h4 class="font-semibold">Or use the published ND Insights value</h4>
            <p class="text-xs text-base-content/60">
              Overall Growth Percentile · {GrowthPercentile.mapping(@editing.metric)["subject"]} · All Grades · All students,
              as published for the school year you choose. Which assessment year applies to
              each review has not been established, so no year is chosen for you. The year,
              population, publication version and file are kept with the result. Published
              values are annual and are never copied into seasonal periods.
            </p>
            <.base_errors form={@editing.published_form} />
            <.select_field
              form={@editing.published_form}
              field={:source_year}
              label="School year of the published value (required)"
              options={[
                {"Select a school year", ""}
                | Enum.map(
                    @published,
                    &{"#{&1.academic_year}: #{published_text(&1)}", &1.academic_year}
                  )
              ]}
            />
            <p :if={@published == []} class="text-xs text-base-content/60" id="published-none">
              No published value has been imported for this measure.
            </p>
            <div
              :if={@chosen}
              class="rounded-lg bg-base-200/60 p-2 text-sm space-y-0.5"
              id="published-preview"
            >
              <div>
                Saving records <strong>{published_text(@chosen)}</strong>
                as the {@period.label} result.
              </div>
              <div class="text-xs text-base-content/70">
                Source year {@chosen.academic_year} · All students · All Grades · Overall Growth
                Percentile · version {@chosen.publication_version}
              </div>
              <div class="text-xs text-base-content/70">
                Workbook baseline: {Display.number(@editing.metric, @editing.metric.baseline_value)} (baseline year not stated in the workbook).
              </div>
            </div>
            <.textarea_field form={@editing.published_form} field={:notes} label="Notes (optional)" />
            <.textarea_field
              :if={@editing.actual}
              form={@editing.published_form}
              field={:correction_reason}
              label="Reason for correction (required)"
            />
            <button type="submit" class="btn btn-primary btn-sm" disabled={!@chosen}>
              {if @editing.actual,
                do: "Save correction from published value",
                else: "Save published value"}
            </button>
          </.form>

          <.form
            for={@editing.rating_form}
            id="rating-form"
            phx-change="change_rating"
            phx-submit="save_rating"
            class="space-y-3 lg:border-l lg:border-base-200 lg:pl-6"
          >
            <h4 :if={!review?(@period)} class="font-semibold">Implementation rating (0–3)</h4>
            <p :if={!review?(@period)} class="text-xs text-base-content/60">
              Seasonal progress check, never a payment input.
            </p>
            <h4 :if={review?(@period)} class="font-semibold" id="review-rating-heading">
              Formal review rating (0–3)
            </h4>
            <p :if={review?(@period)} class="text-xs text-base-content/60">
              {@period.label} rating: an input to the estimated payment. An explicit 0 counts;
              “not applicable” or “unavailable” leaves the checkpoint “Awaiting review”.
            </p>
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
              {cond do
                @editing.rating -> "Save correction"
                review?(@period) -> "Save review rating"
                true -> "Save rating"
              end}
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
  defp value_label(%{unit: :percentile}), do: "Growth percentile (0–100, no % sign)"
  defp value_label(_metric), do: "Value"

  defp unit_hint(%{unit: :percent}), do: "(%, 0–100)"
  defp unit_hint(%{unit: :percentile}), do: "(growth percentile)"
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
