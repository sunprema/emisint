defmodule EmisintWeb.Improvement.StateResultsComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Emisint.Improvement.ResultGoals
  alias EmisintWeb.Improvement.StateResultsComponents

  defp row(measure, {low, high}) do
    %{
      dataset: :assessment_performance,
      academic_year: "2099-2100",
      subject: "Reading",
      grade: "All Grades",
      subgroup: "All",
      assessment_type: "Comp",
      accommodations: "All",
      measure: measure,
      value_state: if(low == high, do: :exact, else: :range),
      value: Decimal.new(low),
      range_low: Decimal.new(low),
      range_high: Decimal.new(high)
    }
  end

  defp render_annual(proficient, advanced, target) do
    goal = %{
      school_year: "2099-2100",
      subject: :ela,
      target_value: Decimal.new(target),
      measure: :proficient_or_advanced,
      includes_alternate: true
    }

    match = ResultGoals.annual(goal, [row("Proficient", proficient), row("Advanced", advanced)])
    render_component(&StateResultsComponents.goal_comparison/1, match: match)
  end

  test "Annual Targets cells use the same bound rule and wording as the state tables" do
    meets = render_annual({"0.2", "0.29"}, {"0.1", "0.1"}, "0.30")
    assert meets =~ "30%–39%"
    assert meets =~ "Derived"
    assert meets =~ "nd-cell-success"
    assert meets =~ "Meets target"

    overlaps = render_annual({"0.2", "0.29"}, {"0", "0.1"}, "0.25")
    assert overlaps =~ "nd-cell-warning"
    assert overlaps =~ "Range overlaps target"

    below = render_annual({"0", "0.1"}, {"0", "0.1"}, "0.25")
    assert below =~ "nd-cell-error"
    assert below =~ "Below target"

    # Exact values: equality meets.
    assert render_annual({"0.2", "0.2"}, {"0.05", "0.05"}, "0.25") =~ "Meets target"
  end

  test "an unpublished year says so, with no color" do
    goal = %{
      school_year: "2099-2100",
      subject: :ela,
      target_value: Decimal.new("0.25"),
      measure: :proficient_or_advanced,
      includes_alternate: true
    }

    html =
      render_component(&StateResultsComponents.goal_comparison/1,
        match: ResultGoals.annual(goal, [])
      )

    assert html =~ "No matching results in the imported data"
    refute html =~ "nd-cell-"
  end
end
