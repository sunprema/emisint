defmodule Emisint.Improvement.Payment do
  @moduledoc """
  Estimated performance-based payment for a goal plan. Shared by the school
  dashboard, the school PDF and `Improvement.PaymentEstimate`.

  **Inputs: formal review ratings only.** Each checkpoint uses the current
  `ImplementationRating` entries recorded in that checkpoint's review period
  (`:review_18m`, `:review_36m`) through `:record_review`. Seasonal ratings,
  target values and actual results are never inputs.

  **Formula** (workbook "Performance-Based Payment", columns C–I; the same
  shared formulas C3:I11 for every participant row 4–11):

      Systems average   = mean of the Systems metrics' review ratings
      Outcomes average  = mean of the Student Outcome metrics' review ratings
      weighted score    = Systems average × Systems weight + Outcomes average × Outcomes weight
      estimated payment = checkpoint allocation × weighted score / max rating (3)

  capped at the checkpoint allocation and rounded to cents (half up).
  Averages are exact; only the final amount is rounded.

  **Completeness** (N/A rule of November 13, 2026). A metric explicitly
  rated **N/A** (`:not_applicable`, the workbook's "N/A" choice) is not
  applicable at this checkpoint: it is left out of the category average and
  of the required count, as the workbook's `AVERAGEIF` leaves out "N/A".
  Every other ("applicable") metric needs a numeric rating (an explicit 0
  counts). A missing rating, or one marked unavailable, leaves the
  checkpoint "Awaiting review": missing values are never treated as N/A or
  as 0. When a category has no numeric rating at all (e.g. every Systems
  metric N/A), the estimate is unavailable (`:category_unavailable`): the
  category is never scored 0 and its weight is never moved to the other.
  (The workbook would skip blanks and show $0 as blank; neither is done.)

  **Weights** per checkpoint, confirmed October 23, 2026: 18-month 70%
  Systems / 30% Student Outcomes; 36-month 30% / 70%.

  **Allocations** come from the goal plan (`allocation_18m`,
  `allocation_36m`, `payment_cap`, `payment_terms_status`,
  `payment_terms_note`, `payment_terms_version`) and are set per checkpoint.
  For all eight ND First participants (reconciled November 13, 2026): the
  18-month allocation is the workbook's $70,000 ("Performance-Based
  Payment"!I2 "18-month payout (up to $70,000)"; I3:I11 `H×70000`). No
  source sets a 36-month allocation, so it is left unset: the 36-month
  checkpoint still shows its averages and weighted score once its ratings
  are complete, with "payment allocation needs confirmation" instead of an
  amount (`:allocation_unconfirmed`). The earlier Fort Yates $35,000 /
  $35,000 split (our own assumption) is withdrawn.

  These are estimates. Nothing here is an actual payment.
  """

  @checkpoint_weights %{
    "nd_first_mou" => [
      %{
        checkpoint: :review_18m,
        label: "18-month review",
        systems_weight: "0.70",
        outcomes_weight: "0.30"
      },
      %{
        checkpoint: :review_36m,
        label: "36-month review",
        systems_weight: "0.30",
        outcomes_weight: "0.70"
      }
    ]
  }

  @label "Estimated payment — provisional terms"
  @unconfigured_label "Estimated payment — not configured"
  @formula "checkpoint allocation × weighted review score ÷ 3 (weighted score = Systems average × Systems weight + Student Outcome average × Student Outcome weight)"

  @doc "The label used for every estimated amount."
  def label, do: @label

  @doc "The payment heading for a plan's terms: \"not configured\" when no split is set."
  def label(%{configured?: false}), do: @unconfigured_label
  def label(_terms), do: @label

  @doc "The formula, as text."
  def formula, do: @formula

  @doc "Confirmed per-checkpoint weights for a program (empty when none are confirmed)."
  def checkpoints(program) do
    @checkpoint_weights
    |> Map.get(program, [])
    |> Enum.map(fn c ->
      %{
        c
        | systems_weight: Decimal.new(c.systems_weight),
          outcomes_weight: Decimal.new(c.outcomes_weight)
      }
    end)
  end

  @doc """
  The plan's payment terms:
  `%{status, cap, allocations: %{review_18m, review_36m}, note, version, configured?}`.
  """
  def terms(plan) do
    allocations = %{review_18m: plan.allocation_18m, review_36m: plan.allocation_36m}

    %{
      status: plan.payment_terms_status,
      cap: plan.payment_cap,
      allocations: allocations,
      note: plan.payment_terms_note,
      version: plan.payment_terms_version,
      # Any checkpoint allocation set: the plan has payment terms. A
      # checkpoint without its own allocation is `:allocation_unconfirmed`.
      configured?: Enum.any?(Map.values(allocations), &(&1 != nil))
    }
  end

  @doc """
  The payment summary for a plan. `review_ratings` maps each checkpoint
  (`:review_18m`, `:review_36m`) to `%{metric_id => current rating}` for that
  review period; a checkpoint without a period or ratings may be omitted.

  Returns `%{terms, label, formula, checkpoints: [checkpoint], combined, …}`
  where each checkpoint has `status` `:estimated | :awaiting_review | :no_terms`.
  """
  def summary(plan, metrics, review_ratings \\ %{}) do
    terms = terms(plan)

    checkpoints =
      plan
      |> Map.get(:program)
      |> checkpoints()
      |> Enum.map(
        &checkpoint(
          &1,
          terms,
          metrics,
          Map.get(review_ratings, &1.checkpoint, %{}),
          plan.max_rating
        )
      )

    %{
      label: label(terms),
      formula: @formula,
      terms: terms,
      checkpoints: checkpoints,
      combined: combined(checkpoints),
      max_rating: plan.max_rating,
      systems_metric_count: Enum.count(metrics, &(&1.category == :systems)),
      outcomes_metric_count: Enum.count(metrics, &(&1.category == :student_outcome))
    }
  end

  defp checkpoint(c, terms, metrics, ratings, max_rating) do
    allocation = terms.allocations[c.checkpoint]
    {na, applicable} = Enum.split_with(metrics, &not_applicable?(ratings[&1.id]))

    missing = for m <- applicable, ratings[m.id] == nil, do: m.code

    not_scored =
      for m <- applicable,
          r = ratings[m.id],
          r != nil,
          not numeric?(r),
          do: {m.code, r.rating_state}

    rated = Enum.filter(applicable, &numeric?(ratings[&1.id]))

    base =
      Map.merge(c, %{
        allocation: allocation,
        systems_average: nil,
        outcomes_average: nil,
        weighted_score: nil,
        estimate: nil,
        missing: missing,
        not_scored: not_scored,
        excluded_na: Enum.map(na, & &1.code),
        empty_categories: [],
        coverage: %{
          applicable: length(applicable),
          rated: length(rated),
          na: length(na),
          total: length(metrics)
        },
        inputs: []
      })

    cond do
      not terms.configured? ->
        Map.put(base, :status, :no_terms)

      missing != [] or not_scored != [] ->
        Map.put(base, :status, :awaiting_review)

      true ->
        estimated(base, c, rated, ratings, allocation, max_rating)
    end
    |> Map.put(:allocation_unconfirmed?, terms.configured? and allocation == nil)
  end

  defp not_applicable?(%{rating_state: :not_applicable}), do: true
  defp not_applicable?(_rating), do: false

  defp numeric?(%{rating_state: :rated, score: score}) when score != nil, do: true
  defp numeric?(_rating), do: false

  # Every applicable metric has a numeric rating (`rated`); N/A metrics are
  # already left out.
  defp estimated(base, c, rated, ratings, allocation, max_rating) do
    systems = for m <- rated, m.category == :systems, do: ratings[m.id].score
    outcomes = for m <- rated, m.category == :student_outcome, do: ratings[m.id].score

    empty =
      for {category, scores} <- [systems: systems, student_outcome: outcomes],
          scores == [],
          do: category

    if empty != [] do
      # A category without any numeric rating: no estimate, never 0 and
      # never reweighted onto the other category.
      base
      |> Map.merge(%{
        empty_categories: empty,
        systems_average: if(systems != [], do: average(systems)),
        outcomes_average: if(outcomes != [], do: average(outcomes))
      })
      |> Map.put(:status, :category_unavailable)
    else
      sa = average(systems)
      oa = average(outcomes)

      weighted =
        Decimal.add(Decimal.mult(sa, c.systems_weight), Decimal.mult(oa, c.outcomes_weight))

      if allocation == nil do
        # Complete ratings, but no allocation for this checkpoint: the score
        # is shown; the amount waits for the allocation to be confirmed.
        %{base | systems_average: sa, outcomes_average: oa, weighted_score: weighted}
        |> Map.put(:status, :allocation_unconfirmed)
      else
        amount_for(base, c, rated, ratings, allocation, max_rating, sa, oa, weighted)
      end
    end
  end

  defp amount_for(base, _c, metrics, ratings, allocation, max_rating, sa, oa, weighted) do
    raw = allocation |> Decimal.mult(weighted) |> Decimal.div(Decimal.new(max_rating))

    amount =
      raw
      |> Decimal.min(allocation)
      |> Decimal.max(Decimal.new(0))
      |> Decimal.round(2, :half_up)

    inputs =
      for m <- metrics,
          do: %{
            "metric" => m.code,
            "category" => to_string(m.category),
            "rating_id" => ratings[m.id].id,
            "score" => ratings[m.id].score
          }

    %{
      base
      | systems_average: sa,
        outcomes_average: oa,
        weighted_score: weighted,
        estimate: amount,
        inputs: inputs
    }
    |> Map.put(:status, :estimated)
  end

  defp average(scores),
    do: Decimal.div(Decimal.new(Enum.sum(scores)), Decimal.new(length(scores)))

  # Both checkpoints estimated: the total. Otherwise only a labeled subtotal
  # of the checkpoints that are complete.
  # A checkpoint whose allocation needs confirmation is never counted as $0:
  # the total stays a labeled subtotal until it is confirmed.
  defp combined(checkpoints) do
    done = Enum.filter(checkpoints, &(&1.status == :estimated))
    subtotal = Enum.reduce(done, Decimal.new(0), &Decimal.add(&1.estimate, &2))
    unconfirmed = for c <- checkpoints, c[:allocation_unconfirmed?], do: c.label

    result =
      cond do
        checkpoints != [] and Enum.all?(checkpoints, &(&1.status == :no_terms)) ->
          %{status: :not_configured, amount: nil, included: []}

        checkpoints != [] and length(done) == length(checkpoints) ->
          %{status: :complete, amount: subtotal, included: Enum.map(done, & &1.label)}

        done != [] ->
          %{status: :partial, amount: subtotal, included: Enum.map(done, & &1.label)}

        true ->
          %{status: :awaiting_review, amount: nil, included: []}
      end

    Map.put(result, :allocation_unconfirmed, unconfirmed)
  end

  # ── Wording (dashboard and PDF) ───────────────────────────────────────────

  @doc "The terms as one sentence, stating that they are not confirmed."
  def terms_text(%{configured?: false}),
    do:
      "Not configured: this school's payment terms (the allocation for each checkpoint) are not set, so no estimate is calculated."

  def terms_text(%{status: :confirmed} = t),
    do: "#{allocations_text(t)} (confirmed terms)."

  # The stored `payment_terms_note` (and each recorded estimate's
  # `terms_note`) keeps the internal provenance; it is not shown to users.
  def terms_text(t), do: provisional_text(t)

  @doc "The provisional-status sentence shown with the payment details."
  def provisional_text(t) do
    workbook =
      if t.allocations.review_18m,
        do:
          "The 18-month amount follows the workbook's “Performance-Based Payment” sheet (rows 4–11, column I: weighted score ÷ 3 × #{dollars(t.allocations.review_18m)}). ",
        else: ""

    unconfirmed =
      if t.allocations.review_36m == nil,
        do:
          "No source sets a 36-month payment allocation, so the 36-month review shows its weighted score and its payment allocation needs confirmation. ",
        else: ""

    ("Provisional estimate, not confirmed contract terms. " <> workbook <> unconfirmed)
    |> String.trim_trailing()
  end

  # Whole dollars, e.g. "$70,000".
  defp dollars(amount), do: amount |> money() |> String.replace_suffix(".00", "")

  @doc """
  The terms for the short payment summary; `terms_text/1` is the
  provisional-status sentence shown once with the calculation details.
  """
  def terms_summary(%{configured?: false} = t), do: terms_text(t)
  def terms_summary(%{status: :confirmed} = t), do: terms_text(t)

  def terms_summary(t),
    do: "Working assumption, not confirmed contract terms: #{allocations_text(t)}."

  defp allocations_text(t),
    do:
      "#{allocation_phrase("18-month review", t.allocations.review_18m)}; #{allocation_phrase("36-month review", t.allocations.review_36m)}"

  defp allocation_phrase(label, nil), do: "#{label}: payment allocation needs confirmation"
  defp allocation_phrase(label, amount), do: "#{label}: up to #{money(amount)}"

  @doc "A checkpoint's allocation cell: the amount, or why there is none."
  def allocation_text(%{allocation: %Decimal{} = a}), do: money(a)
  def allocation_text(%{allocation_unconfirmed?: true}), do: "Needs confirmation"
  def allocation_text(_checkpoint), do: "Not configured"

  @doc "A checkpoint's status line, e.g. \"Awaiting review: 18 of 18 ratings missing\"."
  def status_text(%{status: :estimated, estimate: e}), do: money(e)
  def status_text(%{status: :no_terms}), do: "Not configured"

  def status_text(%{status: :category_unavailable, empty_categories: empty}),
    do:
      "Estimate unavailable: no numeric #{Enum.map_join(empty, " or ", &category_name/1)} ratings (a category is never scored 0 or reweighted)"

  def status_text(%{status: :allocation_unconfirmed, weighted_score: w}),
    do: "Weighted score #{score_text(w)} of 3; payment allocation needs confirmation"

  def status_text(%{status: :awaiting_review, missing: missing, not_scored: not_scored} = c) do
    parts =
      [
        if(missing != [],
          do: "#{length(missing)} review #{plural(missing, "rating")} not recorded"
        ),
        if(not_scored != [],
          do:
            "#{length(not_scored)} marked unavailable (#{Enum.map_join(not_scored, ", ", &elem(&1, 0))})"
        ),
        if(c[:allocation_unconfirmed?], do: "payment allocation needs confirmation")
      ]
      |> Enum.reject(&is_nil/1)

    "Awaiting review: " <> Enum.join(parts, "; ")
  end

  @doc """
  A checkpoint's rating coverage, e.g. "15 of 15 applicable metrics rated ·
  1 N/A excluded" (N/A metrics are left out of the average and the count).
  """
  def coverage_text(%{coverage: %{applicable: a, rated: r, na: na}}),
    do: coverage_phrase(r, a, na)

  @doc "\"15 of 15 applicable metrics rated · 1 N/A excluded\"."
  def coverage_phrase(rated, applicable, na) do
    base =
      "#{rated} of #{applicable} applicable #{if applicable == 1, do: "metric", else: "metrics"} rated"

    if na > 0, do: base <> " · #{na} N/A excluded", else: base
  end

  defp category_name(:systems), do: "Systems"
  defp category_name(:student_outcome), do: "Student Outcome"

  @doc "The combined line, never presenting a subtotal as the total."
  def combined_text(%{status: :complete, amount: a}), do: "#{money(a)} total (both checkpoints)"

  def combined_text(%{
        status: :partial,
        amount: a,
        included: [label],
        allocation_unconfirmed: [_ | _] = u
      }),
      do:
        "Subtotal #{money(a)} (#{label} only); the #{Enum.join(u, ", ")} payment allocation needs confirmation"

  def combined_text(%{status: :partial, amount: a, included: [label]}),
    do: "Subtotal #{money(a)} (#{label} only); the total awaits the other review"

  def combined_text(%{status: :awaiting_review, allocation_unconfirmed: [_ | _] = u}),
    do: "Awaiting review; the #{Enum.join(u, ", ")} payment allocation needs confirmation"

  def combined_text(%{status: :awaiting_review}), do: "Awaiting review"
  def combined_text(%{status: :not_configured}), do: "Not configured"

  @doc "A decimal amount as dollars and cents, e.g. \"$24,500.00\"."
  def money(nil), do: "—"

  def money(%Decimal{} = amount) do
    [whole, cents] =
      amount
      |> Decimal.round(2, :half_up)
      |> Decimal.to_string(:normal)
      |> pad_cents()
      |> String.split(".")

    "$" <>
      (whole |> String.reverse() |> String.replace(~r/(\d{3})(?=\d)/, "\\1,") |> String.reverse()) <>
      "." <> cents
  end

  defp pad_cents(s) do
    case String.split(s, ".") do
      [w] -> w <> ".00"
      [w, c] -> w <> "." <> String.pad_trailing(c, 2, "0")
    end
  end

  @doc "A score or average to two decimals, e.g. \"1.63\"."
  def score_text(nil), do: "—"

  def score_text(%Decimal{} = d),
    do: d |> Decimal.round(2, :half_up) |> Decimal.to_string(:normal)

  defp plural([_], word), do: word
  defp plural(_, word), do: word <> "s"
end
