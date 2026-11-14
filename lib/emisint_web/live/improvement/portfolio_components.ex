defmodule EmisintWeb.Improvement.PortfolioComponents do
  @moduledoc """
  The ND FIRST portfolio summary on `/school-goals`
  (`Emisint.Improvement.Portfolio`): the workbook's "Goals Dashboard" and
  "Performance-Based Payment" sheets, one row per participant.
  """
  use EmisintWeb, :html

  import EmisintWeb.Improvement.SectionComponents, only: [collapsible: 1]

  alias Emisint.Improvement.{Display, Payment, PaymentPreview, Portfolio, Rubric}

  @early [:spr_26, :sum_26, :fal_26, :check_18m]
  @later [:win_27, :spr_27, :sum_27, :fal_27, :win_28, :spr_28]

  attr :summary, :map, required: true

  attr :payment, :map,
    default: nil,
    doc:
      "`%{view: :preview | :formal, preview: PaymentPreview.build/3 result}`; nil shows the formal view"

  attr :open, :any,
    default: nil,
    doc: "the expanded detail sections (a MapSet of \"progress\", \"payment\"); nil: all open"

  def portfolio(assigns) do
    headings = Map.new(Portfolio.progress_columns(), fn {k, h, _c, _kind} -> {k, h} end)
    open? = fn section -> assigns.open == nil or MapSet.member?(assigns.open, section) end

    assigns =
      assign(assigns,
        headings: headings,
        early: @early,
        later: @later,
        latest: latest_average(assigns.summary),
        progress_open?: open?.("progress"),
        payment_open?: open?.("payment")
      )

    ~H"""
    <section id="portfolio" class="space-y-6">
      <div class="flex flex-wrap items-end justify-between gap-3">
        <div class="space-y-1">
          <h2 class="text-lg font-semibold">Portfolio</h2>
          <p class="text-sm text-base-content/70" id="portfolio-scope">
            One row per participant; buildings add no rows. Showing {@summary.coverage.loaded} of {@summary.coverage.listed} participants you can view.
          </p>
        </div>
        <div :if={@open} class="flex gap-2" id="portfolio-section-controls">
          <button
            type="button"
            class="btn btn-sm btn-ghost"
            phx-click="sections"
            phx-value-to="expand"
            id="sections-expand-all"
            disabled={@progress_open? and @payment_open?}
          >
            <.icon name="hero-chevron-double-down" class="size-4" /> Expand all
          </button>
          <button
            type="button"
            class="btn btn-sm btn-ghost"
            phx-click="sections"
            phx-value-to="collapse"
            id="sections-collapse-all"
            disabled={!@progress_open? and !@payment_open?}
          >
            <.icon name="hero-chevron-double-up" class="size-4" /> Collapse all
          </button>
        </div>
      </div>

      <dl class="grid grid-cols-2 md:grid-cols-4 gap-3" id="portfolio-glance">
        <div class="bg-base-100 border border-base-200 rounded-xl p-3">
          <dt class="text-xs text-base-content/60">Participants shown</dt>
          <dd class="text-lg font-semibold tabular-nums" id="glance-participants">
            {@summary.coverage.loaded} of {@summary.coverage.listed}
          </dd>
        </div>
        <div class="bg-base-100 border border-base-200 rounded-xl p-3">
          <dt class="text-xs text-base-content/60">Latest seasonal ratings</dt>
          <dd class="text-lg font-semibold" id="glance-period">
            {if @latest, do: @latest.heading, else: "None recorded"}
          </dd>
        </div>
        <div class="bg-base-100 border border-base-200 rounded-xl p-3">
          <dt class="text-xs text-base-content/60">Systems average</dt>
          <dd id="glance-systems"><.glance a={@latest && @latest.systems} /></dd>
        </div>
        <div class="bg-base-100 border border-base-200 rounded-xl p-3">
          <dt class="text-xs text-base-content/60">Student Outcomes average</dt>
          <dd id="glance-outcomes"><.glance a={@latest && @latest.outcomes} /></dd>
        </div>
      </dl>

      <%!-- Goals Dashboard --%>
      <.section
        id="portfolio-progress"
        section="progress"
        open?={@progress_open?}
        title="Overall Goal Progress — Average Rubric Score"
        summary={progress_summary(@latest)}
      >
        <div class="overflow-x-auto">
          <table class="table table-sm" id="portfolio-progress-table">
            <thead>
              <tr>
                <th rowspan="2">Participant</th>
                <th rowspan="2" class="text-right"># Systems Metrics</th>
                <th rowspan="2" class="text-right"># Student Outcomes Metrics</th>
                <th :for={k <- @early} colspan="2" class="text-center border-l border-base-200">
                  {@headings[k]}<span :if={k == :check_18m} class="block font-normal text-[11px]">formal review</span>
                </th>
              </tr>
              <tr>
                <%= for _k <- @early do %>
                  <th class="text-right border-l border-base-200 font-normal">Systems</th>
                  <th class="text-right font-normal">Student Outcomes</th>
                <% end %>
              </tr>
            </thead>
            <tbody>
              <tr :for={r <- @summary.rows} id={"portfolio-row-#{row_id(r)}"} data-status={r.status}>
                <th class="font-medium align-top"><.participant row={r} /></th>
                <%= if r.status == :loaded do %>
                  <td class="text-right tabular-nums">{r.counts.systems}</td>
                  <td class="text-right tabular-nums">{r.counts.outcomes}</td>
                  <%= for k <- @early do %>
                    <td class="text-right border-l border-base-200">
                      <.avg a={r.columns[k].systems} id={"#{row_id(r)}-#{k}-systems"} />
                    </td>
                    <td class="text-right">
                      <.avg a={r.columns[k].outcomes} id={"#{row_id(r)}-#{k}-outcomes"} />
                    </td>
                  <% end %>
                <% else %>
                  <td colspan={2 + 2 * length(@early)} class="text-sm text-base-content/60">
                    <.row_note row={r} />
                  </td>
                <% end %>
              </tr>
              <.average_row summary={@summary} early={@early} />
            </tbody>
          </table>
        </div>

        <details class="text-sm" id="portfolio-later">
          <summary class="cursor-pointer text-primary">
            Later periods: Win '27 – Spr '28 and the 36-month check
          </summary>
          <div class="overflow-x-auto mt-2">
            <table class="table table-sm" id="portfolio-later-table">
              <thead>
                <tr>
                  <th>Participant</th>
                  <th :for={k <- @later} class="text-right">{@headings[k]}</th>
                  <th class="text-right border-l border-base-200">Systems Check 36 m</th>
                  <th class="text-right">Systems Weighted Score (30%)</th>
                  <th class="text-right">Outcomes Check 36 m</th>
                  <th class="text-right">Outcomes Weighted Score (70%)</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={r <- @summary.rows} id={"portfolio-later-row-#{row_id(r)}"}>
                  <th class="font-medium"><.participant row={r} links?={false} /></th>
                  <%= if r.status == :loaded do %>
                    <td :for={k <- @later} class="text-right">
                      <.avg a={r.columns[k].overall} id={"#{row_id(r)}-#{k}"} />
                    </td>
                    <td class="text-right border-l border-base-200">
                      <.avg a={r.columns.check_36m.systems} id={"#{row_id(r)}-check_36m-systems"} />
                    </td>
                    <td class="text-right tabular-nums">
                      <.plain value={r.columns.check_36m.systems_weighted} />
                    </td>
                    <td class="text-right">
                      <.avg a={r.columns.check_36m.outcomes} id={"#{row_id(r)}-check_36m-outcomes"} />
                    </td>
                    <td class="text-right tabular-nums">
                      <.plain value={r.columns.check_36m.outcomes_weighted} />
                    </td>
                  <% else %>
                    <td colspan={length(@later) + 4} class="text-base-content/60">
                      <.row_note row={r} />
                    </td>
                  <% end %>
                </tr>
              </tbody>
            </table>
          </div>
        </details>

        <div class="flex flex-wrap gap-2 text-xs" id="portfolio-key">
          <span
            :for={{score, label, _d} <- Rubric.levels()}
            class={["badge badge-sm", band_class(score)]}
          >
            {score} — {label} ({band_range(score)})
          </span>
          <span class="text-base-content/60">
            “—” no scored ratings (missing, never zero) · “6/7” 6 of 7 applicable metrics rated · “1 N/A” explicitly not applicable, left out
          </span>
        </div>

        <details class="text-sm text-base-content/70" id="portfolio-progress-how">
          <summary class="cursor-pointer text-primary">How these are calculated</summary>
          <ul class="list-disc pl-5 mt-2 space-y-1">
            <li>
              Source: the workbook's “Goals Dashboard” sheet, one row per ND FIRST participant. District participants appear once; their buildings' pages add no rows or ratings.
            </li>
            <li>
              Metric counts: the plan's Systems and Student Outcome metrics (workbook <span class="font-mono">COUNTIF</span>).
            </li>
            <li>
              Season columns: the mean of the current <strong>seasonal implementation ratings</strong>
              per category (<span class="font-mono">AVERAGEIF</span>). Only scored ratings count; not applicable, unavailable and missing ratings are left out, never counted as zero.
            </li>
            <li>
              18m Check and 36m Check: the same mean of the current
              <strong>formal review ratings</strong>
              recorded at the 18- and 36-month reviews. These are progress views, not payment.
            </li>
            <li>
              Win '27 – Spr '28: one mean over all scored ratings of the period, as the workbook's
              <span class="font-mono">AVERAGE</span>
              does.
            </li>
            <li>
              36-month columns: the workbook gives headings without formulas; the checks use the 18m Check formula and the weighted scores the headed 30% / 70% weights (the confirmed 36-month weights).
            </li>
            <li>
              AVERAGE row: the workbook's <span class="font-mono">AVERAGE</span>
              of the participants' values shown, skipping blanks; the count shows how many participants contributed. The workbook's own rating columns also include its Example School row, so its figures differ.
            </li>
            <li>
              Colors follow the workbook's rubric key. A 3 means “Demonstrated Progress”, not “target met”.
            </li>
          </ul>
        </details>
      </.section>

      <.section
        id="portfolio-payment-section"
        section="payment"
        open?={@payment_open?}
        title="Performance-based payment"
        summary={payment_summary(@payment)}
      >
        <.payment_views summary={@summary} payment={@payment} />
      </.section>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :section, :string, required: true, doc: "the `open` param value"
  attr :open?, :boolean, required: true
  attr :title, :string, required: true
  attr :summary, :string, default: nil
  slot :inner_block, required: true

  # A collapsible detail section (`SectionComponents.collapsible/1`).
  defp section(assigns) do
    ~H"""
    <.collapsible
      id={@id}
      section={@section}
      open?={@open?}
      title={@title}
      summary={@summary}
      heading="h3"
    >
      <div class="space-y-3 p-4">{render_slot(@inner_block)}</div>
    </.collapsible>
    """
  end

  attr :a, :map, default: nil

  defp glance(assigns) do
    ~H"""
    <span
      :if={!@a || !@a.value}
      class="text-sm text-base-content/60"
      data-missing
    >
      No scored ratings
    </span>
    <span :if={@a && @a.value}>
      <span class={["badge tabular-nums", band_class(Portfolio.band(@a.value))]}>
        {Portfolio.number(@a.value)}
      </span>
      <span class="block text-xs text-base-content/60">
        AVERAGE of {@a.of} {if @a.of == 1, do: "participant", else: "participants"}
      </span>
    </span>
    """
  end

  # The latest seasonal column (Spr '26, Sum '26, Fal '26) with any average
  # in the AVERAGE row: `%{heading, systems, outcomes}`, or nil.
  defp latest_average(summary) do
    headings = Map.new(Portfolio.progress_columns(), fn {k, h, _c, _kind} -> {k, h} end)

    @early
    |> Enum.reject(&(&1 == :check_18m))
    |> Enum.reverse()
    |> Enum.find_value(fn k ->
      col = summary.average.columns[k]

      if col.systems.value || col.outcomes.value,
        do: %{heading: headings[k], systems: col.systems, outcomes: col.outcomes}
    end)
  end

  defp progress_summary(nil),
    do: "No seasonal ratings recorded yet; formal 18- and 36-month checks inside."

  defp progress_summary(latest),
    do:
      "Seasonal ratings through #{latest.heading}, formal 18- and 36-month checks and later periods (0–3 rubric)."

  # The payment section header: the selected view and what it currently shows.
  defp payment_summary(nil), do: nil

  defp payment_summary(%{view: :formal}),
    do: "Formal review: estimates from formal 18-month review ratings only."

  defp payment_summary(%{preview: %{period: nil}}),
    do: "Current ratings preview: no period with ratings yet."

  defp payment_summary(%{preview: p}) do
    tones =
      p.rows
      |> Enum.filter(&(&1.status == :loaded))
      |> Enum.frequencies_by(&elem(PaymentPreview.payment_text(&1), 0))

    parts =
      [
        {Map.get(tones, :amount, 0), "estimated"},
        {Map.get(tones, :withheld, 0), "withheld (ratings incomplete)"},
        {Map.get(tones, :no_terms, 0), "payment terms not configured"},
        {Map.get(tones, :allocation_unconfirmed, 0), "payment allocation needs confirmation"}
      ]
      |> Enum.reject(fn {n, _} -> n == 0 end)
      |> Enum.map_join(" · ", fn {n, text} -> "#{n} #{text}" end)

    "Current ratings preview, #{p.period.label}, #{p.checkpoint_label}: #{parts}. Preview only."
  end

  attr :summary, :map, required: true
  attr :payment, :map, default: nil

  # The two payment views, clearly separated: the current-ratings preview
  # (default) and the formal-review table (unchanged).
  defp payment_views(assigns) do
    assigns = assign(assigns, view: (assigns.payment && assigns.payment.view) || :formal)

    ~H"""
    <div class="space-y-3" id="portfolio-payment-views">
      <div role="tablist" class="tabs tabs-box w-fit" id="payment-view-tabs">
        <.link
          :if={@payment}
          patch={@payment.path.(%{"pay" => "preview"})}
          role="tab"
          class={["tab", @view == :preview && "tab-active"]}
          aria-selected={to_string(@view == :preview)}
          id="payment-view-preview"
        >
          Current ratings preview
        </.link>
        <.link
          :if={@payment}
          patch={@payment.path.(%{"pay" => "formal"})}
          role="tab"
          class={["tab", @view == :formal && "tab-active"]}
          aria-selected={to_string(@view == :formal)}
          id="payment-view-formal"
        >
          Formal review
        </.link>
      </div>
      <.preview_payment :if={@view == :preview} preview={@payment.preview} path={@payment.path} />
      <.formal_payment :if={@view == :formal} summary={@summary} />
    </div>
    """
  end

  attr :summary, :map, required: true

  # The formal-review payment table (behavior unchanged).
  defp formal_payment(assigns) do
    ~H"""
    <div class="space-y-3" id="portfolio-payment">
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <h4 class="font-semibold">Performance Based Payments (18-month review)</h4>
        <span class="text-xs text-base-content/60">
          Formal 18-month review ratings only · estimates, not payments
        </span>
      </div>
      <div class="overflow-x-auto">
        <table class="table table-sm" id="portfolio-payment-table">
          <thead>
            <tr>
              <th>Participant</th>
              <th class="text-right">18-month Systems score</th>
              <th class="text-right">Systems Weighted (70%)</th>
              <th class="text-right">Outcomes Score</th>
              <th class="text-right">Outcomes Weighted (30%)</th>
              <th class="text-right">Overall Weighted Score</th>
              <th class="text-right">Performance %</th>
              <th>18-month estimated payment</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={r <- @summary.rows} id={"portfolio-payment-row-#{row_id(r)}"}>
              <th class="font-medium"><.participant row={r} links?={false} /></th>
              <%= if r.status == :loaded do %>
                <td class="text-right">
                  <.avg a={r.payment.systems_score} id={"#{row_id(r)}-pay-systems"} />
                </td>
                <td class="text-right tabular-nums">
                  <.plain value={r.payment.systems_weighted} />
                </td>
                <td class="text-right">
                  <.avg a={r.payment.outcomes_score} id={"#{row_id(r)}-pay-outcomes"} />
                </td>
                <td class="text-right tabular-nums">
                  <.plain value={r.payment.outcomes_weighted} />
                </td>
                <td class="text-right tabular-nums"><.plain value={r.payment.overall} /></td>
                <td class="text-right tabular-nums">
                  {Portfolio.percent(r.payment.performance) || "—"}
                </td>
                <td id={"#{row_id(r)}-estimate"} class="text-sm">
                  <span class={estimate_class(r.payment.estimate)}>
                    {Payment.status_text(r.payment.estimate)}
                  </span>
                </td>
              <% else %>
                <td colspan="7" class="text-base-content/60"><.row_note row={r} /></td>
              <% end %>
            </tr>
          </tbody>
        </table>
      </div>
      <details class="text-sm text-base-content/70" id="portfolio-payment-how">
        <summary class="cursor-pointer text-primary">How these are calculated</summary>
        <ul class="list-disc pl-5 mt-2 space-y-1">
          <li>
            Source: the workbook's “Performance-Based Payment” sheet. No portfolio payment total is shown: the sheet has no total row.
          </li>
          <li>
            Scores: the mean of each category's current formal 18-month review ratings (workbook
            <span class="font-mono">AVERAGEIF</span>
            on the review column). Seasonal ratings never feed payment.
          </li>
          <li>
            Weighted: Systems × 70% and Outcomes × 30%; the overall score is their sum, shown only when both exist. Performance % = overall ÷ 3.
          </li>
          <li>
            Estimated payment: the school dashboard's existing estimate, {Payment.formula()}, with the workbook's $70,000 18-month allocation (the same for every participant, rows 4–11). Unlike the workbook's blank-skipping average, it needs every metric's review rating, so it shows “Awaiting review” until all are recorded.
          </li>
        </ul>
      </details>
    </div>
    """
  end

  attr :preview, :map, required: true
  attr :path, :any, required: true

  defp preview_payment(assigns) do
    ~H"""
    <div class="space-y-3" id="portfolio-preview">
      <div class="space-y-1">
        <h4 class="font-semibold">Estimated payment based on current ratings.</h4>
        <p
          class="text-sm font-medium text-warning-content bg-warning/15 rounded px-2 py-1 w-fit"
          id="preview-disclaimer"
        >
          Preview only. Final payment depends on formal review.
        </p>
      </div>

      <form phx-change="preview" class="flex flex-wrap items-end gap-3" id="preview-form">
        <label class="form-control">
          <span class="label-text text-xs">Reporting period (same for every participant)</span>
          <select name="pay_period" class="select select-sm select-bordered" id="preview-period">
            <option :if={@preview.period == nil} value="" selected>No period with ratings</option>
            <option
              :for={p <- @preview.periods}
              value={p.code}
              selected={@preview.period && p.code == @preview.period.code}
            >
              {p.label}{if p.rated?, do: "", else: " (no ratings yet)"}
            </option>
          </select>
        </label>
        <label class="form-control">
          <span class="label-text text-xs">Checkpoint weights</span>
          <select name="pay_ref" class="select select-sm select-bordered" id="preview-checkpoint">
            <option
              :for={{param, checkpoint, label} <- PaymentPreview.checkpoints()}
              value={param}
              selected={checkpoint == @preview.checkpoint}
            >
              {label}
            </option>
          </select>
        </label>
        <p class="text-xs text-base-content/70 pb-1" id="preview-weights">
          {@preview.checkpoint_label}: Systems {Portfolio.percent(@preview.weights.systems)} · Student Outcomes {Portfolio.percent(
            @preview.weights.outcomes
          )}
        </p>
      </form>

      <div class="overflow-x-auto">
        <table class="table table-sm" id="preview-table">
          <thead>
            <tr>
              <th>Participant</th>
              <th class="text-right">Systems average</th>
              <th class="text-right">Outcomes average</th>
              <th class="text-right">Rating coverage</th>
              <th class="text-right">
                Weighted score <span class="block font-normal text-[11px]">0–3</span>
              </th>
              <th>
                Estimated payment
                <span class="block font-normal text-[11px]">{@preview.checkpoint_label}</span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={r <- @preview.rows} id={"preview-row-#{r.slug}"} data-status={r.status}>
              <th class="font-medium align-top"><.participant row={r} links?={false} /></th>
              <%= if r.status == :loaded do %>
                <td class="text-right align-top">
                  <.preview_avg a={r.systems} id={"preview-#{r.slug}-systems"} />
                </td>
                <td class="text-right align-top">
                  <.preview_avg a={r.outcomes} id={"preview-#{r.slug}-outcomes"} />
                </td>
                <td class="text-right align-top text-sm" id={"preview-#{r.slug}-coverage"}>
                  <span class="tabular-nums">
                    {r.coverage.rated} of {r.coverage.applicable} applicable metrics rated
                  </span>
                  <span :if={r.coverage.na > 0} class="block text-xs text-base-content/60">
                    {r.coverage.na} N/A excluded
                  </span>
                  <span :if={r.coverage.recorded == 0} class="block text-xs text-base-content/60">
                    No ratings recorded for {r.period.label}
                  </span>
                  <span :if={r.coverage.unavailable > 0} class="block text-xs text-base-content/60">
                    {r.coverage.unavailable} marked unavailable
                  </span>
                </td>
                <td class="text-right align-top" id={"preview-#{r.slug}-weighted"}>
                  <span :if={r.weighted} class="tabular-nums">{Portfolio.number(r.weighted)}</span>
                  <span
                    :if={r.weighted && !r.complete?}
                    class="block text-[11px] text-base-content/60"
                  >
                    partial
                  </span>
                  <span :if={!r.weighted} class="text-xs text-base-content/60" data-missing>
                    {PaymentPreview.weighted_reason(r)}
                  </span>
                </td>
                <td class="align-top text-sm" id={"preview-#{r.slug}-payment"}>
                  <% {tone, text} = PaymentPreview.payment_text(r) %>
                  <span
                    class={[
                      tone == :amount && "font-medium",
                      tone != :amount && "text-base-content/70"
                    ]}
                    data-payment={tone}
                  >
                    {text}
                  </span>
                  <span
                    :if={r.provisional_terms?}
                    class="block text-[11px] text-warning"
                    id={"preview-#{r.slug}-provisional"}
                  >
                    Provisional payment terms
                  </span>
                </td>
              <% else %>
                <td colspan="5" class="text-sm text-base-content/60">
                  {PaymentPreview.row_reason(r.status, @preview.period)}
                </td>
              <% end %>
            </tr>
          </tbody>
        </table>
      </div>

      <details class="text-sm text-base-content/70" id="preview-how">
        <summary class="cursor-pointer text-primary">How these are calculated</summary>
        <ul class="list-disc pl-5 mt-2 space-y-1">
          <li>
            Inputs: each participant's current seasonal implementation ratings for the selected period, the same period for everyone. A participant without ratings in that period shows so; no other period is used. ND Insights comparison colors are never ratings.
          </li>
          <li>
            Averages: the mean of each category's numeric ratings. An explicit 0 counts. A metric explicitly rated N/A is left out of the average and of the required count. A missing or unavailable rating is also left out of the average but still counts as required, so the amount is withheld (never zero). If a category has no numeric rating, the estimate is unavailable; its weight is never moved to the other category.
          </li>
          <li>
            Weighted score: Systems average × Systems weight + Student Outcomes average × Student Outcomes weight (18-month 70% / 30%; 36-month 30% / 70%), shown when both averages exist and marked partial when ratings are missing.
          </li>
          <li>
            Estimated payment: the existing formula, {Payment.formula()}, with each plan's own allocation for the selected checkpoint. It is withheld until every metric has a scored rating, and shows “Payment terms not configured” where the plan has none.
          </li>
          <li>
            One row per participant: buildings (including Solen High School) add no row or rating. Nothing here is saved: no review rating, payment record or estimate is created.
          </li>
        </ul>
      </details>
    </div>
    """
  end

  attr :a, :map, required: true
  attr :id, :string, required: true

  defp preview_avg(%{a: %{value: nil}} = assigns) do
    ~H"""
    <span id={@id} class="text-xs text-base-content/60" data-missing>
      {PaymentPreview.average_reason(@a)}
    </span>
    """
  end

  defp preview_avg(assigns), do: avg(assigns)

  attr :row, :map, required: true
  attr :links?, :boolean, default: true

  defp participant(assigns) do
    ~H"""
    <.link
      :if={@links?}
      navigate={~p"/school-goals/#{@row.href}"}
      class="link link-hover"
      id={"portfolio-link-#{@row.slug}"}
    >
      {@row.name}
    </.link>
    <span :if={!@links?}>{@row.name}</span>
    <span class="block text-xs font-normal text-base-content/50">
      {@row.group}<span :if={@row.workbook_note}> · {@row.workbook_note}</span>
    </span>
    """
  end

  attr :row, :map, required: true

  defp row_note(%{row: %{status: :no_access}} = assigns),
    do:
      ~H"<span>The participant record isn't available to you; open its pages for what you can view.</span>"

  defp row_note(assigns), do: ~H"<span>No goal plan recorded.</span>"

  attr :summary, :map, required: true
  attr :early, :list, required: true

  defp average_row(assigns) do
    ~H"""
    <tr
      :if={@summary.average.participants > 0}
      class="border-t-2 border-base-300"
      id="portfolio-average"
    >
      <th>
        AVERAGE
        <span class="block text-xs font-normal text-base-content/50">
          of {@summary.average.participants} {if @summary.average.participants == 1,
            do: "participant",
            else: "participants"} shown
        </span>
      </th>
      <td class="text-right tabular-nums">
        <.plain value={@summary.average.counts.systems.value} />
      </td>
      <td class="text-right tabular-nums">
        <.plain value={@summary.average.counts.outcomes.value} />
      </td>
      <%= for k <- @early do %>
        <td class="text-right border-l border-base-200">
          <.avg_of a={@summary.average.columns[k].systems} id={"average-#{k}-systems"} />
        </td>
        <td class="text-right">
          <.avg_of a={@summary.average.columns[k].outcomes} id={"average-#{k}-outcomes"} />
        </td>
      <% end %>
    </tr>
    """
  end

  attr :a, :map, required: true
  attr :id, :string, required: true

  # A participant's average with its band color and, when partial, its coverage.
  defp avg(%{a: %{value: nil}} = assigns) do
    ~H"""
    <span
      id={@id}
      class="text-base-content/40"
      title={
        if Map.get(@a, :na, 0) == @a.total and @a.total > 0,
          do: "All #{@a.total} N/A: no numeric ratings",
          else: "No scored ratings (0 of #{Map.get(@a, :applicable, @a.total)} applicable)"
      }
      data-missing
    >
      —
    </span>
    <span :if={Map.get(@a, :na, 0) > 0} class="block text-[11px] text-base-content/50">
      {@a.na} N/A
    </span>
    """
  end

  # Partial coverage shows rated/applicable; explicit N/A is shown apart and
  # never counts as missing.
  defp avg(assigns) do
    assigns = assign(assigns, applicable: Map.get(assigns.a, :applicable, assigns.a.total))

    ~H"""
    <span
      id={@id}
      class={["badge badge-sm tabular-nums", band_class(Portfolio.band(@a.value))]}
      title={"#{@a.rated} of #{@applicable} applicable metrics rated" <> if(Map.get(@a, :na, 0) > 0, do: " · #{@a.na} N/A excluded", else: "")}
    >
      {Portfolio.number(@a.value)}
    </span>
    <span :if={@a.rated < @applicable} class="block text-[11px] text-base-content/50">
      {@a.rated}/{@applicable}
    </span>
    <span :if={Map.get(@a, :na, 0) > 0} class="block text-[11px] text-base-content/50">
      {@a.na} N/A
    </span>
    """
  end

  attr :a, :map, required: true
  attr :id, :string, required: true

  # An AVERAGE-row value with how many participants contributed.
  defp avg_of(%{a: %{value: nil}} = assigns) do
    ~H"""
    <span id={@id} class="text-base-content/40" data-missing>—</span>
    """
  end

  defp avg_of(assigns) do
    ~H"""
    <span id={@id} class={["badge badge-sm tabular-nums", band_class(Portfolio.band(@a.value))]}>
      {Portfolio.number(@a.value)}
    </span>
    <span :if={@a.of < @a.participants} class="block text-[11px] text-base-content/50">
      {@a.of} of {@a.participants}
    </span>
    """
  end

  attr :value, :any, required: true

  defp plain(assigns) do
    ~H"""
    <span :if={@value}>{Portfolio.number(@value)}</span><span
      :if={!@value}
      class="text-base-content/40"
      data-missing
    >—</span>
    """
  end

  defp row_id(%{slug: slug}), do: slug

  defp band_class(nil), do: "badge-ghost"

  defp band_class(score) do
    case Display.score_tone(score) do
      :success -> "badge-soft badge-success nd-text-success"
      :info -> "badge-soft badge-info nd-text-info"
      :warning -> "badge-soft badge-warning nd-text-warning"
      :error -> "badge-soft badge-error nd-text-error"
    end
  end

  defp band_range(3), do: "2.5+"
  defp band_range(2), do: "1.5–2.49"
  defp band_range(1), do: "0.50–1.49"
  defp band_range(0), do: "0.49 or less"

  defp estimate_class(%{status: :estimated}), do: "font-medium"
  defp estimate_class(_), do: "text-base-content/60"
end
