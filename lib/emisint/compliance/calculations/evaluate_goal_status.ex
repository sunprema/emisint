defmodule Emisint.Compliance.Calculations.EvaluateGoalStatus do
  use Ash.Resource.Calculation

  @moduledoc """
  Derives goal evaluation status from stored snapshot data on a GoalEvaluation record.

  Can also be called directly via `evaluate/5` from `ComputeGoalActualValue`.

  Returns one of: :exceeds, :meets, :approaching, :below, :insufficient_data
  """

  @impl Ash.Resource.Calculation
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      evaluate(
        record.actual_value,
        record.target_value,
        record.comparison_operator || :gte,
        record.exceeds_threshold,
        record.approaching_threshold
      )
    end)
  end

  @doc """
  Pure evaluation function — maps actual vs threshold values to a status atom.

  - nil actual_value              → :insufficient_data
  - actual >= exceeds_threshold   → :exceeds
  - actual >= target_value        → :meets
  - actual >= approaching_threshold → :approaching
  - otherwise                     → :below
  """
  def evaluate(nil, _target, _op, _exceeds, _approaching), do: :insufficient_data

  def evaluate(actual, target, comparison_op, exceeds_threshold, approaching_threshold) do
    op = comparison_op || :gte

    cond do
      exceeds_threshold && compare(actual, exceeds_threshold, op) -> :exceeds
      compare(actual, target, op) -> :meets
      approaching_threshold && compare(actual, approaching_threshold, op) -> :approaching
      true -> :below
    end
  end

  defp compare(actual, threshold, :gte), do: Decimal.compare(actual, threshold) in [:gt, :eq]
  defp compare(actual, threshold, :gt), do: Decimal.compare(actual, threshold) == :gt
  defp compare(actual, threshold, :lte), do: Decimal.compare(actual, threshold) in [:lt, :eq]
  defp compare(actual, threshold, :lt), do: Decimal.compare(actual, threshold) == :lt
  defp compare(actual, threshold, :eq), do: Decimal.compare(actual, threshold) == :eq
end
