defmodule EmisintWeb.Improvement.PortfolioComponents do
  @moduledoc """
  The ND FIRST portfolio summary on `/school-goals`
  (`Emisint.Improvement.Portfolio`): the workbook's "Goals Dashboard" and
  "Performance-Based Payment" sheets, one row per participant.
  """
  use EmisintWeb, :html

  alias Emisint.Improvement.{Display, Payment, Portfolio, Rubric}

  @early [:spr_26, :sum_26, :fal_26, :check_18m]
  @later [:win_27, :spr_27, :sum_27, :fal_27, :win_28, :spr_28]

  attr :summary, :map, required: true

  def portfolio(assigns) do
    headings = Map.new(Portfolio.progress_columns(), fn {k, h, _c, _kind} -> {k, h} end)
    assigns = assign(assigns, headings: headings, early: @early, later: @later)

    ~H"""
    <section id="portfolio" class="space-y-6">
      <div class="space-y-1">
        <h2 class="text-lg font-semibold">Portfolio</h2>
        <p class="text-sm text-base-content/70 max-w-3xl" id="portfolio-scope">
          One row per ND FIRST participant, from the workbook's “Goals Dashboard” and
          “Performance-Based Payment” sheets. District participants appear once; their
          buildings' pages add no rows or ratings. Showing {@summary.coverage.loaded} of {@summary.coverage.listed} listed participants with data you can view.
        </p>
      </div>

      <%!-- Goals Dashboard --%>
      <div class="bg-base-100 border border-base-200 rounded-xl p-4 space-y-3" id="portfolio-progress">
        <div class="flex flex-wrap items-baseline justify-between gap-2">
          <h3 class="font-semibold">Overall Goal Progress — Average Rubric Score</h3>
          <span class="text-xs text-base-content/60">
            Seasonal implementation ratings and formal review checks (0–3)
          </span>
        </div>

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
            “—” no scored ratings (missing, never zero) · “6/7” only 6 of 7 metrics scored
          </span>
        </div>

        <details class="text-sm text-base-content/70" id="portfolio-progress-how">
          <summary class="cursor-pointer text-primary">How these are calculated</summary>
          <ul class="list-disc pl-5 mt-2 space-y-1">
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
      </div>

      <%!-- Performance-Based Payment --%>
      <div class="bg-base-100 border border-base-200 rounded-xl p-4 space-y-3" id="portfolio-payment">
        <div class="flex flex-wrap items-baseline justify-between gap-2">
          <h3 class="font-semibold">Performance Based Payments (18-month review)</h3>
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
        <p class="text-xs text-base-content/60">
          No portfolio payment total is shown: the workbook's payment sheet has no total row.
        </p>
        <details class="text-sm text-base-content/70" id="portfolio-payment-how">
          <summary class="cursor-pointer text-primary">How these are calculated</summary>
          <ul class="list-disc pl-5 mt-2 space-y-1">
            <li>
              Scores: the mean of each category's current formal 18-month review ratings (workbook
              <span class="font-mono">AVERAGEIF</span>
              on the review column). Seasonal ratings never feed payment.
            </li>
            <li>
              Weighted: Systems × 70% and Outcomes × 30%; the overall score is their sum, shown only when both exist. Performance % = overall ÷ 3.
            </li>
            <li>
              Estimated payment: the school dashboard's existing estimate, {Payment.formula()}. It uses each plan's 18-month allocation instead of the workbook's single $70,000 and needs every metric's review rating, so it shows “Awaiting review” until all are recorded and “Not configured” where the plan has no payment terms.
            </li>
          </ul>
        </details>
      </div>
    </section>
    """
  end

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
      title={"No scored ratings (0 of #{@a.total})"}
      data-missing
    >
      —
    </span>
    """
  end

  defp avg(assigns) do
    ~H"""
    <span
      id={@id}
      class={["badge badge-sm tabular-nums", band_class(Portfolio.band(@a.value))]}
      title={"#{@a.rated} of #{@a.total} metrics scored"}
    >
      {Portfolio.number(@a.value)}
    </span>
    <span :if={@a.rated < @a.total} class="block text-[11px] text-base-content/50">
      {@a.rated}/{@a.total}
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
