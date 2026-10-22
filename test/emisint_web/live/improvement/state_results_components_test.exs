defmodule EmisintWeb.Improvement.StateResultsComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias EmisintWeb.Improvement.StateResultsComponents

  @match %{
    year: "2099-2100",
    subject: "Reading",
    assessment_type: "Comp",
    grade: "All Grades",
    subgroup: "All"
  }

  defp render_comparison(status, low, high) do
    comparison = %{
      status: status,
      low: Decimal.new(low),
      high: Decimal.new(high),
      match: @match,
      derived: true
    }

    render_component(&StateResultsComponents.goal_comparison/1, comparison: comparison)
  end

  test "range results show the labeled derived range and no verdict" do
    html = render_comparison(:pending_range_clarification, "0.2", "0.39")

    assert html =~ "20%–39%"
    assert html =~ "Derived"
    assert html =~ "Derived by adding the published Proficient and Advanced values"
    assert html =~ "Goal status pending range clarification"
    assert html =~ "No verdict"
    refute html =~ "Meets goal"
    refute html =~ "Below goal"
  end

  test "exact results show a verdict, labeled derived and compared as published" do
    for {status, label} <- [meets: "Meets goal", below: "Below goal"] do
      html = render_comparison(status, "0.35", "0.35")
      assert html =~ "35%"
      assert html =~ "Derived"
      assert html =~ label
      assert html =~ "published as exact values and are compared as published"
      refute html =~ "pending range clarification"
    end
  end
end
