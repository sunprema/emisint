defmodule Emisint.Improvement.GoalStatusTest do
  use ExUnit.Case, async: true

  alias Emisint.Improvement.GoalStatus

  # Synthetic metrics, results and periods: no real Fort Yates result exists yet.
  defp metric(attrs \\ []) do
    Map.merge(
      %{
        unit: :percent,
        direction: :higher_is_better,
        baseline_value: Decimal.new("0.6"),
        target_18m: Decimal.new("0.9"),
        target_36m: Decimal.new("0.95"),
        flags: [],
        source_values: %{}
      },
      Map.new(attrs)
    )
  end

  defp exact(value), do: %{value_state: :exact, value: Decimal.new(value)}

  @seasonal %{kind: :seasonal, label: "Sum '26"}
  @review_18m %{kind: :review_18m, label: "18-Month Review"}
  @review_36m %{kind: :review_36m, label: "36-Month Review"}

  test "a seasonal result is never compared with an 18- or 36-month target" do
    status = GoalStatus.evaluate(metric(), exact("0.99"), @seasonal)
    assert %{status: :neutral, reason: :no_target_due} = status
    assert GoalStatus.summary(status) == "No target due this period"
  end

  test "the target due at a review is used, in the metric's direction" do
    assert %{status: :meets} = GoalStatus.evaluate(metric(), exact("0.92"), @review_18m)
    assert %{status: :meets} = GoalStatus.evaluate(metric(), exact("0.9"), @review_18m)
    below = GoalStatus.evaluate(metric(), exact("0.85"), @review_18m)
    assert %{status: :below} = below
    assert GoalStatus.summary(below) == "18-month target 90% · Below target"

    assert %{status: :below, target_text: "95%"} =
             GoalStatus.evaluate(metric(), exact("0.92"), @review_36m)

    lower = metric(direction: :lower_is_better, target_18m: Decimal.new("0.39"))
    assert %{status: :meets} = GoalStatus.evaluate(lower, exact("0.3"), @review_18m)
    assert %{status: :below} = GoalStatus.evaluate(lower, exact("0.45"), @review_18m)
  end

  test "missing results, non-exact results and unconfirmed targets stay neutral" do
    status = GoalStatus.evaluate(metric(), nil, @review_18m)
    assert %{status: :neutral, reason: :not_reported} = status
    assert GoalStatus.summary(status) == "18-month target 90% · Not compared: no result reported"
    assert GoalStatus.summary(GoalStatus.evaluate(metric(), nil, @seasonal)) == nil

    range = %{value_state: :range, range_low: Decimal.new("0.8"), range_high: Decimal.new("0.95")}

    assert %{status: :neutral, reason: :result_not_exact} =
             GoalStatus.evaluate(metric(), range, @review_18m)

    flagged = metric(target_36m: nil, flags: [:target_36m_needs_confirmation])
    status = GoalStatus.evaluate(flagged, exact("0.99"), @review_36m)
    assert %{status: :neutral, reason: :target_not_comparable} = status
    assert GoalStatus.summary(status) =~ "Needs confirmation · Not compared"

    text_target =
      metric(
        target_18m: nil,
        flags: [:value_as_text],
        source_values: %{"target_18m" => %{"raw" => "> 50%", "cell" => "X1"}}
      )

    assert %{status: :neutral, reason: :target_not_comparable, target_text: "> 50%"} =
             GoalStatus.evaluate(text_target, exact("0.6"), @review_18m)
  end
end
