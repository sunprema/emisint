defmodule EmisintWeb.Improvement.GoalResultComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias Emisint.Improvement.GoalStatus
  alias EmisintWeb.Improvement.Components

  # Synthetic statuses: review-period results can't be recorded yet.
  defp render_status(status) do
    assigns = %{status: status}

    rendered_to_string(~H"""
    <Components.goal_result status={@status} id="status-X">92%</Components.goal_result>
    """)
  end

  defp status(value, kind) do
    metric = %{
      unit: :percent,
      direction: :higher_is_better,
      target_18m: Decimal.new("0.9"),
      target_36m: Decimal.new("0.95"),
      flags: [],
      source_values: %{}
    }

    GoalStatus.evaluate(metric, %{value_state: :exact, value: Decimal.new(value)}, %{kind: kind})
  end

  test "result, applicable target and status appear together, colored only for a verdict" do
    meets = render_status(status("0.92", :review_18m))
    assert meets =~ ~r/nd-text-success[^>]*>\s*92%/
    assert meets =~ "18-month target 90% · Meets target"

    below = render_status(status("0.85", :review_18m))
    assert below =~ ~r/nd-text-error[^>]*>\s*92%/
    assert below =~ "18-month target 90% · Below target"

    seasonal = render_status(status("0.92", :seasonal))
    assert seasonal =~ "No target due this period"
    refute seasonal =~ "nd-text-"
  end

  # Synthetic ratings: Fort Yates' recorded ratings are only 1s and 2s.
  test "each implementation rating is one badge with the score, full label and rubric color" do
    for {score, label, tone} <- [
          {0, "Not Started", "nd-text-error"},
          {1, "Some Progress", "nd-text-warning"},
          {2, "Implementation on Track", "nd-text-info"},
          {3, "Demonstrated Progress", "nd-text-success"}
        ] do
      assigns = %{entry: %{rating_state: :rated, score: score}}

      html =
        rendered_to_string(~H"""
        <Components.rating_value entry={@entry} />
        """)

      assert html =~ ~r/class="[^"]*badge-soft[^"]*#{tone}[^"]*"[^>]*>\s*#{score} · #{label}\s*</
    end
  end
end
