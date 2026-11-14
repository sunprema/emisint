defmodule Emisint.Improvement.PaymentPreview do
  @moduledoc """
  "Estimated payment based on current ratings": a read-only preview on the
  `/school-goals` portfolio, next to the formal-review payment table, and
  (November 13, 2026) the main figure on each participant page's payment
  card and in its PDF, for the page's selected period (`for_participant/4`).

  It applies the existing payment formula and completeness rule
  (`Payment.summary/3`) to the **current seasonal implementation ratings of
  one reporting period**, as if they were the selected checkpoint's review
  ratings:

    * **Period.** One seasonal period, the same for every participant
      (default: the latest seasonal period in which any shown participant
      has a recorded rating). A participant without ratings in it shows that
      reason; another period is never used instead.
    * **Checkpoint.** 18-month (Systems 70% / Outcomes 30%) or 36-month
      (30% / 70%), from `Payment.checkpoints/1`.
    * **Averages** follow the portfolio's `AVERAGEIF` rule
      (`Portfolio.average/3`): scored ratings only, an explicit 0 counts, a
      missing, not applicable or unavailable rating is left out, never
      zero. Partial averages are shown with their coverage.
    * **Weighted score**: Systems average × Systems weight + Outcomes average
      × Outcomes weight, when both averages exist; marked partial when any
      rating is missing.
    * **Estimated payment**: `Payment.summary/3` with the plan's own terms
      and the selected checkpoint's allocation. It is withheld until every
      metric has a scored rating, and "Payment terms not configured" when
      the plan has none (no allocation is invented or copied from another
      plan). A checkpoint without its own allocation (the 36-month review,
      November 13, 2026) shows its weighted score and "Payment allocation
      needs confirmation".

  One row per participant (`Portfolio.summary/1` rows, from each
  participant's main record): buildings, including Solen High School, never
  add a row or a rating. Nothing here writes: no review rating, payment
  estimate or other record is created. ND Insights comparison colors are
  never used.
  """

  alias Emisint.Improvement.{Payment, Portfolio}

  @program "nd_first_mou"

  @doc "The checkpoints a preview can use: `[{param, checkpoint, label}]`."
  def checkpoints,
    do: [{"18m", :review_18m, "18-month checkpoint"}, {"36m", :review_36m, "36-month checkpoint"}]

  @doc "The checkpoint for a request parameter (default 18-month)."
  def checkpoint("36m"), do: :review_36m
  def checkpoint(_param), do: :review_18m

  @doc """
  The seasonal periods offered, in plan order, from the shown participants'
  plans: `[%{code, label, rated?}]`, `rated?` when any shown participant has a
  recorded rating in it.
  """
  def periods(%{rows: rows}) do
    loaded = Enum.filter(rows, &(&1.status == :loaded))

    loaded
    |> Enum.flat_map(fn r -> Enum.filter(r.defs.periods, &(&1.kind == :seasonal)) end)
    |> Enum.uniq_by(& &1.code)
    |> Enum.sort_by(& &1.position)
    |> Enum.map(fn p ->
      %{code: p.code, label: p.label, rated?: Enum.any?(loaded, &(recorded(&1, p.code) != %{}))}
    end)
  end

  @doc """
  The default period: the latest seasonal period with a recorded rating for
  any shown participant, or nil when there is none.
  """
  def default_period(summary) do
    summary |> periods() |> Enum.filter(& &1.rated?) |> List.last() |> then(&(&1 && &1.code))
  end

  @doc """
  The preview for `period_code` (a seasonal period code; an unknown code
  selects nothing rather than another period) and `checkpoint`.
  """
  def build(summary, period_code, checkpoint) do
    periods = periods(summary)
    period = Enum.find(periods, &(&1.code == period_code))
    weights = Enum.find(Payment.checkpoints(@program), &(&1.checkpoint == checkpoint))

    %{
      periods: periods,
      period: period,
      checkpoint: checkpoint,
      checkpoint_label:
        Enum.find_value(checkpoints(), fn {_p, c, label} -> c == checkpoint && label end),
      weights: %{systems: weights.systems_weight, outcomes: weights.outcomes_weight},
      rows: Enum.map(summary.rows, &row(&1, period, weights))
    }
  end

  @doc """
  One participant's preview for the period selected on its own page
  (November 13, 2026): the same `build/3` the portfolio uses, on `defs`
  (`Dashboard.load_plan/2`) and that period's current ratings
  (`%{metric_id => rating}`). The result is `build/3`'s map plus `:row`.

  A review period selects nothing (`:review_period`): the preview uses
  seasonal ratings only, and no other period is used instead.
  """
  def for_participant(defs, period, period_ratings, checkpoint \\ :review_18m) do
    input = %{
      slug: nil,
      name: nil,
      href: nil,
      group: nil,
      workbook_note: nil,
      status: :loaded,
      defs: defs,
      ratings: %{period.id => period_ratings}
    }

    preview = build(%{rows: [input]}, period.code, checkpoint)

    row =
      if period.kind == :seasonal,
        do: hd(preview.rows),
        else: input |> base(:review_period) |> Map.put(:period, period)

    Map.put(preview, :row, row)
  end

  @preview_note "Preview only; final payment depends on formal review."

  @doc "The note shown with every preview figure."
  def preview_note, do: @preview_note

  @doc """
  The headline of a participant's preview: `{tone, text}`, e.g.
  `{:amount, "Estimated payment: $48,611.11"}`, or `payment_text/1`'s
  reason when there is no amount.
  """
  def headline(%{status: :loaded} = row) do
    case payment_text(row) do
      {:amount, money} -> {:amount, "Estimated payment: " <> money}
      other -> other
    end
  end

  def headline(%{status: status} = row), do: {:unavailable, row_reason(status, row[:period])}

  @doc "What a preview is based on, e.g. \"Sum '26 ratings · 18-month checkpoint (Systems 70% / Student Outcomes 30%)\"."
  def basis_text(%{row: %{status: :review_period, period: p}, checkpoint_label: c}),
    do: "#{p.label} (formal review period) · #{c}"

  def basis_text(%{period: p, checkpoint_label: c, weights: w}),
    do:
      "#{if p, do: p.label <> " ratings", else: "No reporting period"} · #{c} (Systems #{pct(w.systems)} / Student Outcomes #{pct(w.outcomes)})"

  defp pct(weight),
    do: "#{weight |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_string()}%"

  defp row(%{status: :loaded} = r, nil, _weights), do: base(r, :no_period)

  defp row(%{status: :loaded} = r, period, weights) do
    case Enum.find(r.defs.periods, &(&1.code == period.code)) do
      nil -> base(r, :period_not_in_plan)
      p -> figures(r, p, Map.get(r.ratings, p.id, %{}), weights)
    end
  end

  defp row(r, _period, _weights), do: base(r, r.status)

  defp base(r, status),
    do: Map.take(r, [:slug, :name, :href, :group, :workbook_note]) |> Map.put(:status, status)

  defp figures(r, period, ratings, weights) do
    metrics = r.defs.metrics
    systems = Portfolio.average(metrics, ratings, :systems)
    outcomes = Portfolio.average(metrics, ratings, :student_outcome)

    weighted =
      if systems.value && outcomes.value,
        do:
          Decimal.add(
            Decimal.mult(systems.value, weights.systems_weight),
            Decimal.mult(outcomes.value, weights.outcomes_weight)
          )

    # The existing formula and completeness rule, on this period's ratings
    # for the selected checkpoint. Pure: nothing is recorded.
    estimate =
      r.defs.plan
      |> Payment.summary(metrics, %{weights.checkpoint => ratings})
      |> Map.fetch!(:checkpoints)
      |> Enum.find(&(&1.checkpoint == weights.checkpoint))

    terms = Payment.terms(r.defs.plan)
    recorded = map_size(Map.take(ratings, Enum.map(metrics, & &1.id)))
    c = estimate.coverage

    r
    |> base(:loaded)
    |> Map.merge(%{
      period: period,
      systems: systems,
      outcomes: outcomes,
      # The payment rule's own coverage: N/A metrics are excluded from the
      # applicable count; missing and unavailable ones are not.
      coverage: %{
        recorded: recorded,
        rated: c.rated,
        applicable: c.applicable,
        na: c.na,
        total: c.total,
        missing: length(estimate.missing),
        unavailable: length(estimate.not_scored)
      },
      weighted: weighted,
      complete?: c.rated == c.applicable,
      estimate: estimate,
      terms: terms,
      # Labeled only where this checkpoint has an amount to label.
      provisional_terms?:
        terms.allocations[weights.checkpoint] != nil and terms.status != :confirmed
    })
  end

  defp recorded(%{defs: defs, ratings: ratings}, code) do
    case Enum.find(defs.periods, &(&1.code == code)) do
      nil -> %{}
      p -> Map.get(ratings, p.id, %{})
    end
  end

  # ── Wording ───────────────────────────────────────────────────────────────

  @doc "Why an average is missing, or nil when it exists."
  def average_reason(%{value: nil, total: 0}), do: "No metrics in this category"

  def average_reason(%{value: nil, total: t, na: t}) when t > 0,
    do: "All #{t} N/A: no numeric ratings"

  def average_reason(%{value: nil} = a),
    do: "No scored ratings (0 of #{Map.get(a, :applicable, a.total)} applicable)"

  def average_reason(_average), do: nil

  @doc "Why there is no weighted score, or nil."
  def weighted_reason(%{weighted: nil}), do: "Needs both averages"
  def weighted_reason(_row), do: nil

  @doc """
  The payment cell: `{tone, text}` with tone `:amount | :withheld |
  :no_terms | :allocation_unconfirmed | :unavailable`.
  """
  def payment_text(%{estimate: %{status: :estimated, estimate: amount}}),
    do: {:amount, Payment.money(amount)}

  def payment_text(%{estimate: %{status: :no_terms}}),
    do: {:no_terms, "Payment terms not configured"}

  def payment_text(%{estimate: %{status: :allocation_unconfirmed}}),
    do: {:allocation_unconfirmed, "Payment allocation needs confirmation"}

  def payment_text(%{estimate: %{status: :category_unavailable} = e}),
    do: {:unavailable, Payment.status_text(e)}

  def payment_text(%{estimate: %{status: :awaiting_review} = e, coverage: c}) do
    parts =
      [
        if(e.missing != [],
          do: "#{length(e.missing)} of #{c.applicable} applicable ratings not recorded"
        ),
        if(e.not_scored != [], do: "#{length(e.not_scored)} marked unavailable"),
        if(e[:allocation_unconfirmed?], do: "payment allocation needs confirmation")
      ]
      |> Enum.reject(&is_nil/1)

    {:withheld, "Withheld: " <> Enum.join(parts, "; ")}
  end

  @doc "The reason shown for a row without figures."
  def row_reason(:no_access, _period),
    do: "The participant record isn't available to you; open its pages for what you can view."

  def row_reason(:no_plan, _period), do: "No goal plan recorded."
  def row_reason(:no_period, _period), do: "No reporting period selected."

  def row_reason(:review_period, period),
    do:
      "#{period.label} is a formal review period. The preview uses one seasonal period's ratings; choose a seasonal period to see it (no other period is used)."

  def row_reason(:period_not_in_plan, period),
    do: "This plan has no #{period.label} period; no other period is used."
end
