defmodule Emisint.Improvement.TextTargetComparisonsTest do
  @moduledoc """
  Goal-comparison colors beyond Fort Yates: text targets ("< 18%", "55-60%",
  "< 22% or within 7% State Avg"), Valley Middle's and Drayton's
  candidate engagement mappings (no verdict), and the participants whose workbook
  goals stay uncompared (with the reason shown near the measure).
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

  describe "candidate mappings: Valley G3-M1 and Drayton G4-M1" do
    test "Drayton G4-M1 shows the value and \"< 18%\" target gray, with the evidence, no verdict" do
      rows = [engagement(:engagement_overall, "Disengaged", "2024-2025", {"0.25", "0.29"})]
      plan = plan(Seeds.Drayton)

      for ref <- [:review_18m, :review_36m] do
        match =
          ResultGoals.for_filters(rows, filters("2024-2025", ref), plan).engagement[
            :engagement_overall
          ]["Disengaged"]

        assert %{code: "G4-M1", status: :gray, tone: :muted, reasons: [:mapping_unconfirmed]} =
                 match

        assert match.value == "25%–29%"
        assert match.candidate?
        assert match.basis =~ "Drayton Goals!D21"
        assert ResultGoals.short_label(match) == "Gray: candidate mapping, awaiting confirmation"

        assert ResultGoals.explanation(match) =~
                 "evidence below is to investigate, not a confirmation"
      end

      m36 =
        ResultGoals.for_filters(rows, filters("2024-2025", :review_36m), plan).engagement[
          :engagement_overall
        ]["Disengaged"]

      # The target is still parsed and shown.
      assert {:bound, "<", _} = m36.spec
      assert ResultGoals.goal_line(m36) =~ "36-month target < 18%"

      [note | _] =
        ResultGoals.section_notes(
          :engagement,
          ResultGoals.for_filters(rows, filters("2024-2025", :review_36m), plan).engagement
        )

      assert note =~ "Candidate mapping, awaiting confirmation"
      assert note =~ "Evidence to investigate"
    end

    test "Valley G3-M1 gets no verdict, even where its \"< 22%\" part would be met" do
      plan = plan(Seeds.ValleyMiddle)
      rows = [engagement(:engagement_overall, "Disengaged", "2020-2021", "0.18")]

      match =
        ResultGoals.for_filters(rows, filters("2020-2021", :review_36m), plan).engagement[
          :engagement_overall
        ]["Disengaged"]

      assert %{code: "G3-M1", status: :gray, reasons: [:mapping_unconfirmed]} = match
      assert {:compound, "<", _, "within 7% State Avg"} = match.spec
      assert match.basis =~ "Valley Goals!D18"
    end

    test "\"Engaged\" metrics (Drayton G4-M2, Valley G5-M2) aren't mapped, and the notes say why" do
      rows = [engagement(:engagement_overall, "Committed", "2024-2025", {"0.25", "0.29"})]

      for module <- [Seeds.Drayton, Seeds.ValleyMiddle] do
        g = ResultGoals.for_filters(rows, filters("2024-2025", :review_36m), plan(module))
        refute Map.has_key?(g.engagement[:engagement_overall], "Committed")
        config = ResultGoals.config(module.school())
        assert config.section_notes.engagement =~ "Not compared"
        assert config.section_notes.engagement =~ "candidate mapping"
      end

      assert Map.keys(ResultGoals.config(Seeds.Drayton.school()).candidates) == ["G4-M1"]
      assert Map.keys(ResultGoals.config(Seeds.ValleyMiddle.school()).candidates) == ["G3-M1"]
    end
  end

  describe "participants without a supported workbook comparison" do
    test "Dunseith, Mandaree and Warwick match nothing, and each section says why" do
      for module <- [Seeds.Dunseith, Seeds.Mandaree, Seeds.Warwick] do
        config = ResultGoals.config(module.school())
        assert config.workbook == [], inspect(module)
        assert is_binary(config.section_notes.engagement)
        assert is_binary(config.section_notes.achievement)
      end

      assert ResultGoals.config(Seeds.Dunseith.school()).section_notes.engagement =~
               "matches no published area value"

      assert ResultGoals.config(Seeds.Warwick.school()).section_notes.achievement =~
               "relative targets"
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
