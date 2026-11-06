defmodule Emisint.Improvement.Payment do
  @moduledoc """
  Estimated performance-based payment for a goal plan. Shared by the school
  dashboard, the school PDF and `Improvement.PaymentEstimate`.

  **Inputs: formal review ratings only.** Each checkpoint uses the current
  `ImplementationRating` entries recorded in that checkpoint's review period
  (`:review_18m`, `:review_36m`) through `:record_review`. Seasonal ratings,
  target values and actual results are never inputs.

  **Formula** (workbook "Performance-Based Payment", columns C–I, with the
  provisional allocation in place of the workbook's single $70,000):

      Systems average   = mean of the Systems metrics' review ratings
      Outcomes average  = mean of the Student Outcome metrics' review ratings
      weighted score    = Systems average × Systems weight + Outcomes average × Outcomes weight
      estimated payment = checkpoint allocation × weighted score / max rating (3)

  capped at the checkpoint allocation and rounded to cents (half up).
  Averages are exact; only the final amount is rounded.

  **Completeness.** Every metric in the plan needs a scored review rating
  (an explicit 0 counts). A missing rating, or one marked not applicable or
  unavailable, leaves the checkpoint "Awaiting review": nothing is excluded
  and the weights are never renormalized. (The workbook's `AVERAGEIF` would
  skip blanks and shows $0 as blank; neither is done here.)

  **Weights** per checkpoint, confirmed October 23, 2026: 18-month 70%
  Systems / 30% Student Outcomes; 36-month 30% / 70%.

  **Cap and allocations** come from the goal plan (`payment_cap`,
  `allocation_18m`, `allocation_36m`, `payment_terms_status`,
  `payment_terms_note`, `payment_terms_version`). For Fort Yates they are
  provisional: $70,000 total, $35,000 per checkpoint. Ram authorized
  using a best-estimate rule on November 1, 2026 pending confirmation; the
  total and the equal split are our selected assumptions, not terms he
  specified, and not confirmed contract terms.

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

  @label "Estimated payment — provisional cap and split"
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
      configured?: plan.payment_cap != nil and Enum.all?(Map.values(allocations), &(&1 != nil))
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

    base =
      Map.merge(c, %{
        allocation: allocation,
        systems_average: nil,
        outcomes_average: nil,
        weighted_score: nil,
        estimate: nil,
        missing: [],
        not_scored: [],
        inputs: []
      })

    missing = for m <- metrics, ratings[m.id] == nil, do: m.code

    not_scored =
      for m <- metrics,
          r = ratings[m.id],
          r != nil,
          r.rating_state != :rated or r.score == nil,
          do: {m.code, r.rating_state}

    cond do
      not terms.configured? ->
        Map.put(base, :status, :no_terms)

      missing != [] or not_scored != [] ->
        %{base | missing: missing, not_scored: not_scored} |> Map.put(:status, :awaiting_review)

      true ->
        estimated(base, c, metrics, ratings, allocation, max_rating)
    end
  end

  defp estimated(base, c, metrics, ratings, allocation, max_rating) do
    systems = for m <- metrics, m.category == :systems, do: ratings[m.id].score
    outcomes = for m <- metrics, m.category == :student_outcome, do: ratings[m.id].score

    if systems == [] or outcomes == [] do
      Map.put(base, :status, :no_terms)
    else
      sa = average(systems)
      oa = average(outcomes)

      weighted =
        Decimal.add(Decimal.mult(sa, c.systems_weight), Decimal.mult(oa, c.outcomes_weight))

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
  end

  defp average(scores),
    do: Decimal.div(Decimal.new(Enum.sum(scores)), Decimal.new(length(scores)))

  # Both checkpoints estimated: the total. Otherwise only a labeled subtotal
  # of the checkpoints that are complete.
  defp combined(checkpoints) do
    done = Enum.filter(checkpoints, &(&1.status == :estimated))
    subtotal = Enum.reduce(done, Decimal.new(0), &Decimal.add(&1.estimate, &2))

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
  end

  # ── Wording (dashboard and PDF) ───────────────────────────────────────────

  @doc "The terms as one sentence, stating that they are not confirmed."
  def terms_text(%{configured?: false}),
    do:
      "Not configured: this school's payment terms (the allocation for each checkpoint) are not set, so no estimate is calculated."

  def terms_text(%{status: :confirmed} = t),
    do: "#{money(t.cap)} total: #{allocations_text(t)} (confirmed terms)."

  # The stored `payment_terms_note` (and each recorded estimate's
  # `terms_note`) keeps the internal provenance; it is not shown to users.
  # The summary already states the cap and split (`terms_summary/1`), so the
  # details give the provisional-status sentence once, on its own.
  def terms_text(t), do: provisional_text(t)

  @doc "The provisional-status sentence shown with the payment details."
  def provisional_text(%{allocations: %{review_18m: a, review_36m: a}} = t),
    do:
      "Provisional estimate based on an assumed #{dollars(t.cap)} total per school, split equally between the 18-month and 36-month checkpoints. Final payment terms are pending confirmation."

  def provisional_text(t),
    do:
      "Provisional estimate based on an assumed #{dollars(t.cap)} total per school (#{allocations_text(t)}). Final payment terms are pending confirmation."

  # Whole dollars, e.g. "$70,000".
  defp dollars(amount), do: amount |> money() |> String.replace_suffix(".00", "")

  @doc """
  The terms for the short payment summary; `terms_text/1` is the
  provisional-status sentence shown once with the calculation details.
  """
  def terms_summary(%{configured?: false} = t), do: terms_text(t)
  def terms_summary(%{status: :confirmed} = t), do: terms_text(t)

  def terms_summary(t),
    do:
      "Working assumption, not confirmed contract terms: #{money(t.cap)} total per school across both checkpoints, " <>
        "#{allocations_text(t)}."

  defp allocations_text(t),
    do:
      "#{money(t.allocations.review_18m)} to the 18-month review and #{money(t.allocations.review_36m)} to the 36-month review"

  @doc "A checkpoint's status line, e.g. \"Awaiting review: 18 of 18 ratings missing\"."
  def status_text(%{status: :estimated, estimate: e}), do: money(e)
  def status_text(%{status: :no_terms}), do: "Not configured"

  def status_text(%{status: :awaiting_review, missing: missing, not_scored: not_scored}) do
    parts =
      [
        if(missing != [],
          do: "#{length(missing)} review #{plural(missing, "rating")} not recorded"
        ),
        if(not_scored != [],
          do:
            "#{length(not_scored)} marked not applicable or unavailable (#{Enum.map_join(not_scored, ", ", &elem(&1, 0))})"
        )
      ]
      |> Enum.reject(&is_nil/1)

    "Awaiting review: " <> Enum.join(parts, "; ")
  end

  @doc "The combined line, never presenting a subtotal as the total."
  def combined_text(%{status: :complete, amount: a}), do: "#{money(a)} total (both checkpoints)"

  def combined_text(%{status: :partial, amount: a, included: [label]}),
    do: "Subtotal #{money(a)} (#{label} only); the total awaits the other review"

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
