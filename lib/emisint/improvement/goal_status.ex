defmodule Emisint.Improvement.GoalStatus do
  @moduledoc """
  Whether a metric's result for a reporting period meets its own target.
  Shared by the school dashboard and the school PDF.

  * **Applicable target.** A target applies only in the period it belongs
    to: the 18-month target at the 18-Month Review (`kind: :review_18m`),
    the 36-month target at the 36-Month Review (`kind: :review_36m`). Seasonal
    periods have no target due, so a seasonal result is never compared with
    an 18- or 36-month target, and no interim targets or "on track"
    trajectories are derived.
  * **Comparable values.** The target must be a confirmed number
    (`Display.target/2` returns `{:number, _}`: not flagged for confirmation,
    not workbook text or an Excel date) and the result an exact value.
    Ranges, suppressed and unavailable results are not compared.
  * **Direction.** `:higher_is_better` meets the target at or above it;
    `:lower_is_better` at or below it.

  Returns `%{status: :meets | :below | :neutral, reason, target_label,
  target_text}`.
  """

  alias Emisint.Improvement.Display

  def evaluate(metric, actual, period) do
    {field, label} = applicable(period)
    target = field && Display.target(metric, field)

    base = %{
      status: :neutral,
      target_label: label,
      target_text: target_text(target)
    }

    cond do
      actual == nil -> Map.put(base, :reason, :not_reported)
      field == nil -> Map.put(base, :reason, :no_target_due)
      actual.value_state != :exact -> Map.put(base, :reason, :result_not_exact)
      not match?({:number, _}, target) -> Map.put(base, :reason, :target_not_comparable)
      true -> compare(base, actual.value, Map.fetch!(metric, field), metric.direction)
    end
  end

  defp applicable(%{kind: :review_18m}), do: {:target_18m, "18-month target"}
  defp applicable(%{kind: :review_36m}), do: {:target_36m, "36-month target"}
  defp applicable(_period), do: {nil, nil}

  defp compare(base, value, target, direction) do
    order = Decimal.compare(value, target)

    meets? =
      case direction do
        :lower_is_better -> order in [:lt, :eq]
        _ -> order in [:gt, :eq]
      end

    if meets?,
      do: %{base | status: :meets} |> Map.put(:reason, :meets),
      else: %{base | status: :below} |> Map.put(:reason, :below)
  end

  defp target_text({_shape, text}), do: text
  defp target_text(_), do: nil

  @doc "A short status line, e.g. \"18-month target 90% · Meets target\"."
  def summary(%{reason: :not_reported, target_label: nil}), do: nil

  def summary(%{reason: :not_reported} = s),
    do: "#{s.target_label} #{s.target_text || "not set"} · Not compared: no result reported"

  def summary(%{reason: :no_target_due}), do: "No target due this period"
  def summary(%{reason: :meets} = s), do: "#{s.target_label} #{s.target_text} · Meets target"
  def summary(%{reason: :below} = s), do: "#{s.target_label} #{s.target_text} · Below target"

  def summary(%{reason: :result_not_exact} = s),
    do: "#{s.target_label} #{s.target_text} · Not compared: the result isn't an exact value"

  def summary(%{reason: :target_not_comparable} = s),
    do: "#{s.target_label}: #{s.target_text} · Not compared: no confirmed numeric target"
end
