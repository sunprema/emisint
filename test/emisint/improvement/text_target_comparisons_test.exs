defmodule Emisint.Improvement.TextTargetComparisonsTest do
  @moduledoc """
  Goal-comparison colors beyond Fort Yates: text targets ("< 18%", "55-60%",
  "< 22% or within 7% State Avg") and the records whose workbook goals stay
  uncompared (with the reason shown near the measure). The November 12, 2026
  mapping decisions are in `goal_comparison_decisions_test.exs`.
  """
  use ExUnit.Case, async: true

  alias Emisint.Improvement.ResultGoals
  alias Emisint.Improvement.Seeds

  defp plan(module),
    do: %{
      school: module.school(),
      metrics: module.metrics(),
      annual_goals: module.annual_assessment_goals()
    }

  defp filters(year, ref), do: %{year: year, type: "Comp", subgroup: "All", reference: ref}

  defp engagement(dataset, level, year, value) do
    base = %{dataset: dataset, academic_year: year, engagement_level: level, unit: :proportion}

    case value do
      {low, high} ->
        Map.merge(base, %{
          value_state: :range,
          value: nil,
          range_low: Decimal.new(low),
          range_high: Decimal.new(high)
        })

      v ->
        Map.merge(base, %{
          value_state: :exact,
          value: Decimal.new(v),
          range_low: nil,
          range_high: nil
        })
    end
  end

  defp metric(unit, raw, direction \\ :lower_is_better) do
    %{
      unit: unit,
      direction: direction,
      flags: [],
      target_36m: nil,
      source_values: %{"target_36m" => %{"cell" => "X!P1", "raw" => raw}}
    }
  end

  defp spec(unit, raw), do: ResultGoals.target_spec(metric(unit, raw), :target_36m)

  describe "target_spec/2: numeric text targets are comparable" do
    test "inequalities, ranges and compound targets" do
      assert spec(:percent, "< 18%") == {:bound, "<", Decimal.new("0.18")}
      assert spec(:percent, " > 50%") == {:bound, ">", Decimal.new("0.5")}
      assert spec(:percent, "≥ 35%") == {:bound, ">=", Decimal.new("0.35")}
      assert spec(:percent, "55-60%") == {:band, Decimal.new("0.55"), Decimal.new("0.6")}
      assert spec(:percent, "4–8%") == {:band, Decimal.new("0.04"), Decimal.new("0.08")}

      assert spec(:percent, "< 22% or within 7% State Avg") ==
               {:compound, "<", Decimal.new("0.22"), "within 7% State Avg"}

      assert spec(:score, "< 2.4") == {:bound, "<", Decimal.new("2.4")}
    end

    test "missing targets and other wording stay gray" do
      assert spec(:percent, "n/a") == :none
      assert spec(:percent, nil) == :none
      assert spec(:percent, "Dec 2-3%") == :not_comparable
      assert spec(:percent, "Inc 4-6%") == :not_comparable
      assert spec(:percent, "70% @ Level 2+") == :not_comparable
      assert spec(:percent, "50% K-6; 100% 7-12") == :not_comparable
      # A percent metric's text without "%" is ambiguous (18 or 0.18?).
      assert spec(:percent, "< 18") == :not_comparable
      assert spec(:percent, "60-55%") == :not_comparable
    end

    test "a stored number is used as before" do
      m = %{metric(:percent, "0.3") | target_36m: Decimal.new("0.3")}
      assert ResultGoals.target_spec(m, :target_36m) == {:number, Decimal.new("0.3")}
    end
  end

  describe "classify_bound/3: strict inequalities" do
    test "below 18% meets; 18% or more misses; a range across it overlaps" do
      t = Decimal.new("0.18")
      d = &Decimal.new/1

      assert ResultGoals.classify_bound("<", {d.("0.15"), d.("0.17")}, t) == :meets
      assert ResultGoals.classify_bound("<", {d.("0.18"), d.("0.18")}, t) == :misses
      assert ResultGoals.classify_bound("<", {d.("0.15"), d.("0.19")}, t) == :overlaps
      assert ResultGoals.classify_bound(">", {d.("0.35"), d.("0.35")}, d.("0.35")) == :misses
      assert ResultGoals.classify_bound(">=", {d.("0.35"), d.("0.35")}, d.("0.35")) == :meets
    end
  end

  # The candidate mappings (Valley G3-M1, Drayton G4-M1) and the unmapped
  # "Engaged" metrics were confirmed by the user on November 12, 2026; see
  # `goal_comparison_decisions_test.exs`.

  describe "participants without a supported workbook comparison" do
    test "Mandaree matches nothing, and each section says why" do
      config = ResultGoals.config(Seeds.Mandaree.school())
      assert config.workbook == []
      assert is_binary(config.section_notes.engagement)
      assert is_binary(config.section_notes.achievement)
    end

    test "buildings never inherit the district's workbook matches" do
      for district <- [Seeds.Drayton, Seeds.Dunseith, Seeds.Mandaree, Seeds.Warwick],
          building <- district.buildings() do
        config = ResultGoals.config(building.school())
        assert config.workbook == [], inspect(building)
        assert config.candidates == %{}
      end
    end

    test "Fort Yates keeps its assumption-based comparisons" do
      config = ResultGoals.config(Seeds.FortYates.school())
      assert config.candidates == %{}
      assert config.assumptions == %{assessment_type: "Comp", engagement_population: :schoolwide}
    end
  end
end
