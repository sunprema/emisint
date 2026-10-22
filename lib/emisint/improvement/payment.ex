defmodule Emisint.Improvement.Payment do
  @moduledoc """
  Performance-based payment summary for a goal plan.

  The payment is computed **only** from formal 18-month review ratings:

      ((avg Systems review × systems_weight + avg Outcomes review × outcomes_weight)
        / max_rating) × payment_cap

  Formal review ratings are not recorded yet (Phase 3, `ReviewRating`), so
  the status is always `:awaiting_review` and no amount is produced. Seasonal
  implementation ratings and actual results are deliberately not inputs to
  this module: they must never yield a payment amount.

  Category totals are counted from the plan's metrics, not hard-coded.
  """

  @type summary :: %{
          status: :awaiting_review,
          amount: nil,
          payment_cap: Decimal.t() | nil,
          systems_weight: Decimal.t() | nil,
          outcomes_weight: Decimal.t() | nil,
          max_rating: integer(),
          systems_metric_count: non_neg_integer(),
          outcomes_metric_count: non_neg_integer()
        }

  @spec summary(map(), [map()]) :: summary()
  def summary(plan, metrics) do
    %{
      status: :awaiting_review,
      amount: nil,
      payment_cap: plan.payment_cap,
      systems_weight: plan.systems_weight,
      outcomes_weight: plan.outcomes_weight,
      max_rating: plan.max_rating,
      systems_metric_count: Enum.count(metrics, &(&1.category == :systems)),
      outcomes_metric_count: Enum.count(metrics, &(&1.category == :student_outcome))
    }
  end
end
