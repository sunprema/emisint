defmodule Emisint.NdInsights.ParserTest do
  use ExUnit.Case, async: true

  alias Emisint.NdInsights.Parser

  @fixtures Path.expand("../../fixtures/nd_insights", __DIR__)
  @fort_yates "4300429212"

  defp parse(file, ids \\ [@fort_yates]) do
    {:ok, parsed} = Parser.parse_file(Path.join(@fixtures, file), institution_ids: ids)
    parsed
  end

  defp find(observations, attrs) do
    Enum.filter(observations, fn o -> Enum.all?(attrs, fn {k, v} -> Map.get(o, k) == v end) end)
  end

  describe "Assessment Performance (real Fort Yates rows, 2024-25)" do
    setup do
      %{parsed: parse("Insights-AssessmentPerformance-CSV-2024-2025-v20251113.csv")}
    end

    test "detects the dataset, publication version and one observation per level", %{
      parsed: parsed
    } do
      assert parsed.dataset == :assessment_performance
      assert parsed.publication_version == "20251113"
      assert parsed.errors == []
      # 36 published rows × 4 levels
      assert length(parsed.observations) == 144
      assert Enum.all?(parsed.observations, &(&1.institution_name == "Fort Yates Middle School"))
    end

    test "keeps ranges as low/high, never a midpoint", %{parsed: parsed} do
      all = [
        academic_year: "2024-2025",
        subject: "Reading",
        assessment_type: "Comp",
        grade: "All Grades",
        subgroup: "All"
      ]

      assert [partially] = find(parsed.observations, [{:measure, "Partially"} | all])
      assert partially.value_state == :range
      assert Decimal.equal?(partially.range_low, "0.3")
      assert Decimal.equal?(partially.range_high, "0.39")
      assert partially.value == nil
      assert partially.source_text == "0.3|0.39"

      assert [novice] = find(parsed.observations, [{:measure, "Novice"} | all])
      assert Decimal.equal?(novice.range_low, "0.4") and Decimal.equal?(novice.range_high, "0.49")

      assert [advanced] = find(parsed.observations, [{:measure, "Advanced"} | all])
      assert Decimal.equal?(advanced.range_low, 0) and Decimal.equal?(advanced.range_high, "0.1")
    end

    test "keeps every source dimension and the verbatim row", %{parsed: parsed} do
      [obs | _] = parsed.observations
      assert obs.accommodations == "All"
      assert obs.raw_row["InstitutionID"] == @fort_yates
      assert obs.natural_key =~ "assessment_performance|2024-2025|4300429212|"

      subgroups = parsed.observations |> Enum.map(& &1.subgroup) |> Enum.uniq() |> Enum.sort()
      assert subgroups == ["All", "Female", "Homeless", "Male", "Non-Homeless"]
    end
  end

  describe "suppression, exact values and errors (synthetic file)" do
    setup do
      %{
        parsed:
          parse("Insights-AssessmentPerformance-CSV-2099-2100-v20990101.csv", ["TEST000001"])
      }
    end

    test "low == high is exact; * and empty cells are suppressed with the source text kept", %{
      parsed: parsed
    } do
      reading = find(parsed.observations, subject: "Reading")

      assert [%{value_state: :exact} = novice] = find(reading, measure: "Novice")
      assert Decimal.equal?(novice.value, "0.18")

      assert [%{value_state: :suppressed, value: nil, range_low: nil, source_text: "*|*"}] =
               find(reading, measure: "Partially")

      assert [%{value_state: :suppressed, source_text: "|"}] =
               find(reading, measure: "Proficient")
    end

    test "out-of-range values are errors, not clamped", %{parsed: parsed} do
      assert [%{measure: "Novice", message: "range is outside 0–1"}] = parsed.errors
      assert find(parsed.observations, grade: "8", measure: "Novice") == []
    end

    test "only requested institutions are returned", %{parsed: parsed} do
      refute Enum.any?(parsed.observations, &(&1.institution_id == "TEST000002"))
    end
  end

  test "Growth Rate keeps levels and percentiles as their own units and trims grade padding" do
    parsed = parse("Insights-GrowthRate-CSV-2024-2025-v20251113.csv")
    assert parsed.dataset == :growth_rate

    grade7 = find(parsed.observations, subject: "ELA", grade: "7", subgroup: "All")

    assert [%{unit: :level, value_state: :exact} = level] =
             find(grade7, measure: "OverallGrowthLevel")

    assert Decimal.equal?(level.value, 2)
    assert level.raw_row["Grade"] == "7 "

    assert [%{unit: :percentile} = pct] = find(grade7, measure: "OverallGrowthPercentile")
    assert Decimal.equal?(pct.value, 35)

    assert [%{unit: :proportion, value_state: :range}] = find(grade7, measure: "Approaches")
  end

  test "Engagement Survey files are unpivoted by academic year and keep text ranges" do
    parsed = parse("Insights-Engagement-Emotional-All-CSV-v20251202.csv")
    assert parsed.dataset == :engagement_emotional
    # 3 engagement levels × 8 academic years
    assert length(parsed.observations) == 24

    assert [obs] =
             find(parsed.observations, engagement_level: "Committed", academic_year: "2024-2025")

    assert obs.value_state == :range
    assert Decimal.equal?(obs.range_low, "0.30") and Decimal.equal?(obs.range_high, "0.34")
    assert obs.source_text == "0.30-0.34"
    assert obs.district_name == "Ft Yates Public School District"
  end

  test "unrecognized files are rejected" do
    path = Path.join(System.tmp_dir!(), "nd-unknown-#{System.unique_integer([:positive])}.csv")
    File.write!(path, "A,B\n1,2\n")
    on_exit(fn -> File.rm(path) end)

    assert {:error, message} = Parser.parse_file(path, institution_ids: [@fort_yates])
    assert message =~ "unrecognized"
  end

  test "publication versions come from the -vYYYYMMDD stamp" do
    assert Parser.publication_version("Insights-GrowthRate-CSV-2024-2025-v20251113.csv") ==
             "20251113"

    assert Parser.publication_version("renamed.csv") == nil
  end
end
