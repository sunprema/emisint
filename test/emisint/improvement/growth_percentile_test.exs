defmodule Emisint.Improvement.GrowthPercentileTest do
  use Emisint.DataCase, async: true

  import Emisint.ImprovementFixtures

  require Ash.Query

  alias Emisint.Improvement.{
    ActualResult,
    Display,
    GoalStatus,
    GrowthPercentile,
    Metric,
    Seeds
  }

  alias Emisint.NdInsights.{SourceFile, StateResult}

  @fort_yates "4300429212"

  # The pre-decision definitions, as earlier seeds stored them.
  @percent_definitions %{
    "G2-M3" => {"0.38", "0.43", "0.51", 15},
    "G3-M3" => {"0.41", "0.46", "0.52", 22}
  }

  defp revert_to_percent!(org, code) do
    {baseline, t18, t36, row} = Map.fetch!(@percent_definitions, code)
    cell = &%{"cell" => "Ft Yates Goals!#{&1}#{row}", "raw" => &2}

    org
    |> metric!(code)
    |> Ash.Changeset.for_update(
      :apply_unit_decision,
      %{
        description: "Percentage of students met state growth expectations",
        unit: :percent,
        performance_measure: :met_growth_expectation,
        baseline_value: Decimal.new(baseline),
        target_18m: Decimal.new(t18),
        target_36m: Decimal.new(t36),
        source_values: %{
          "baseline" => cell.("D", baseline),
          "target_18m" => cell.("H", t18),
          "target_36m" => cell.("P", t36)
        }
      },
      tenant: org.id,
      authorize?: false
    )
    |> Ash.update!()
  end

  defp definition_fields(metric) do
    Map.take(metric, [
      :description,
      :unit,
      :performance_measure,
      :baseline_value,
      :target_18m,
      :target_36m,
      :source_values,
      :flags
    ])
    |> Map.update!(:baseline_value, &Decimal.to_string(&1, :normal))
    |> Map.update!(:target_18m, &Decimal.to_string(&1, :normal))
    |> Map.update!(:target_36m, &Decimal.to_string(&1, :normal))
  end

  defp history(org, metric) do
    ActualResult
    |> Ash.Query.filter(metric_id == ^metric.id)
    |> Ash.read!(tenant: org.id, authorize?: false)
  end

  defp record!(org, user, metric, period_code, value) do
    Ash.create!(
      ActualResult,
      %{
        metric_id: metric.id,
        reporting_period_id: period!(org, period_code).id,
        value_state: :exact,
        value: Decimal.new(value),
        measurement_date: ~D[2026-10-15]
      },
      action: :record,
      tenant: org.id,
      actor: user
    )
  end

  describe "fresh seed" do
    setup do
      %{org: seeded_organization!()}
    end

    test "G2-M3 and G3-M3 are growth percentiles with the workbook numbers", %{org: org} do
      for {code, label, values} <- [
            {"G2-M3", "ELA", ["38", "43", "51"]},
            {"G3-M3", "Math", ["41", "46", "52"]}
          ] do
        m = metric!(org, code)
        assert %{unit: :percentile, performance_measure: :growth_percentile} = m
        assert m.description == "Overall growth percentile (#{label})"

        assert Enum.map(
                 [m.baseline_value, m.target_18m, m.target_36m],
                 &Decimal.to_string(&1, :normal)
               ) ==
                 values

        # Original workbook cells and wording are preserved as provenance.
        assert m.source_values["description"]["raw"] ==
                 "Percentage of students met state growth expectations"

        assert m.source_values["baseline"]["raw"] =~ ~r/^0\.\d\d$/
        assert m.source_values["unit_decision"]["date"] == "2026-10-31"

        assert m.source_values["nd_insights"] == %{
                 "dataset" => "growth_rate",
                 "measure" => "OverallGrowthPercentile",
                 "subject" => label,
                 "grade" => "All Grades",
                 "subgroup" => "All"
               }

        # Shown without a percent sign.
        assert Display.target(m, :baseline_value) == {:number, hd(values)}
        assert Display.unit_label(m) == "Growth percentile"
      end
    end

    test "no other metric changes unit", %{org: org} do
      others =
        Metric
        |> Ash.read!(tenant: org.id, authorize?: false)
        |> Enum.reject(&(&1.code in GrowthPercentile.codes()))

      assert Enum.all?(others, &(&1.unit == :percent))
      assert Display.target(metric!(org, "G2-M1"), :baseline_value) == {:number, "22%"}
    end

    test "re-running the seed reports nothing converted and no drift", %{org: org} do
      assert {:ok, report} =
               Seeds.run(org.id, schools: [Seeds.FortYates], workbook_ratings?: false)

      assert report.converted == []
      assert report.drift == []
    end
  end

  describe "converting an existing database" do
    setup do
      org = seeded_organization!()
      fresh = Map.new(GrowthPercentile.codes(), &{&1, definition_fields(metric!(org, &1))})
      for code <- GrowthPercentile.codes(), do: revert_to_percent!(org, code)
      %{org: org, fresh: fresh, contributor: contributor!(org)}
    end

    test "produces the fresh-seed definition and is repeat-safe", %{org: org, fresh: fresh} do
      assert metric!(org, "G2-M3").unit == :percent

      assert {:ok, %{converted: converted, restated: 0}} = GrowthPercentile.run(org.id)
      assert Enum.sort(converted) == ["G2-M3", "G3-M3"]

      for code <- GrowthPercentile.codes() do
        assert definition_fields(metric!(org, code)) == fresh[code]
      end

      assert {:ok, %{converted: [], unchanged: unchanged, drift: []}} =
               GrowthPercentile.run(org.id)

      assert Enum.sort(unchanged) == ["G2-M3", "G3-M3"]

      for code <- GrowthPercentile.codes() do
        assert definition_fields(metric!(org, code)) == fresh[code]
      end
    end

    test "the seed applies the conversion and then reports no drift", %{org: org} do
      assert {:ok, first} =
               Seeds.run(org.id, schools: [Seeds.FortYates], workbook_ratings?: false)

      assert length(first.converted) == 2
      assert first.drift == []

      assert {:ok, second} =
               Seeds.run(org.id, schools: [Seeds.FortYates], workbook_ratings?: false)

      assert second.converted == []
      assert second.drift == []
    end

    test "results entered as percentages are restated by an appended correction", %{
      org: org,
      contributor: contributor
    } do
      metric = metric!(org, "G2-M3")
      original = record!(org, contributor, metric, "fal_26", "0.45")

      assert {:error, reason} = GrowthPercentile.run(org.id)
      assert reason =~ "pass actor:"
      # Nothing changed: the conversion runs in one transaction.
      assert metric!(org, "G2-M3").unit == :percent

      admin = user!(nil, :system_admin)
      assert {:ok, %{restated: 1}} = GrowthPercentile.run(org.id, actor: admin)

      entries = history(org, metric)
      assert length(entries) == 2
      restated = Enum.find(entries, &(&1.source == :unit_conversion))
      assert restated.corrects_id == original.id
      assert Decimal.equal?(restated.value, "45")
      assert restated.author_id == contributor.id
      assert restated.recorded_by_id == admin.id
      assert restated.measurement_date == original.measurement_date
      assert restated.source_ref == GrowthPercentile.conversion_ref()

      # The original entry is untouched and is displayed in its original unit.
      kept = Enum.find(entries, &(&1.id == original.id))
      assert Decimal.equal?(kept.value, "0.45")
      assert GrowthPercentile.legacy_entry_ids(entries) == MapSet.new([original.id])

      # Repeat: nothing more is appended.
      assert {:ok, %{restated: 0, unchanged: [_, _]}} = GrowthPercentile.run(org.id, actor: admin)
      assert length(history(org, metric)) == 2
    end

    test "a metric matching neither definition is drift and left untouched", %{org: org} do
      org
      |> metric!("G3-M3")
      |> Ash.Changeset.for_update(:apply_unit_decision, %{target_18m: Decimal.new("0.47")},
        tenant: org.id,
        authorize?: false
      )
      |> Ash.update!()

      assert {:ok, %{converted: ["G2-M3"], drift: ["G3-M3"]}} = GrowthPercentile.run(org.id)
      assert %{unit: :percent} = m = metric!(org, "G3-M3")
      assert Decimal.equal?(m.target_18m, "0.47")
    end
  end

  test "other schools' G2-M3 and G3-M3 are not converted" do
    org = seeded_organization!(schools: [Seeds.FortYates, Seeds.Oberon, Seeds.ValleyMiddle])

    others =
      Metric
      |> Ash.Query.filter(code in ["G2-M3", "G3-M3"])
      |> Ash.read!(tenant: org.id, authorize?: false)

    assert length(others) == 6
    assert Enum.count(others, &(&1.unit == :percentile)) == 2
    assert Enum.count(others, &(&1.unit == :percent)) == 4
  end

  describe "policies and validation" do
    setup do
      org = seeded_organization!()
      %{org: org, contributor: contributor!(org), metric: metric!(org, "G2-M3")}
    end

    test "only the system can apply a unit decision or restate a result", ctx do
      assert {:error, %Ash.Error.Forbidden{}} =
               ctx.metric
               |> Ash.Changeset.for_update(:apply_unit_decision, %{description: "Edited"},
                 tenant: ctx.org.id,
                 actor: ctx.contributor
               )
               |> Ash.update()

      entry = record!(ctx.org, ctx.contributor, ctx.metric, "fal_26", "40")

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.create(
                 ActualResult,
                 %{
                   corrects_id: entry.id,
                   value_state: :exact,
                   value: Decimal.new("41"),
                   correction_reason: "x",
                   source_ref: "x"
                 },
                 action: :convert_unit,
                 tenant: ctx.org.id,
                 actor: ctx.contributor
               )
    end

    test "growth percentiles are stored as entered, within 0–100", ctx do
      entry = record!(ctx.org, ctx.contributor, ctx.metric, "fal_26", "38.5")
      assert Decimal.equal?(entry.value, "38.5")
      assert Display.actual(entry, ctx.metric) == "38.5"

      assert {:error, error} =
               Ash.create(
                 ActualResult,
                 %{
                   metric_id: ctx.metric.id,
                   reporting_period_id: period!(ctx.org, "win_27").id,
                   value_state: :exact,
                   value: Decimal.new("101"),
                   measurement_date: ~D[2026-10-15]
                 },
                 action: :record,
                 tenant: ctx.org.id,
                 actor: ctx.contributor
               )

      assert :value in error_fields(error)
    end
  end

  describe "status against the checkpoint target (real definitions, synthetic results)" do
    setup do
      org = seeded_organization!()
      %{org: org, metric: metric!(org, "G2-M3"), lower: metric!(org, "G2-M2")}
    end

    defp exact(value), do: %{value_state: :exact, value: Decimal.new(value)}

    test "higher-is-better percentile: above and equal meet, below does not", ctx do
      review_18m = period!(ctx.org, "review_18m")
      review_36m = period!(ctx.org, "review_36m")

      above = GoalStatus.evaluate(ctx.metric, exact("44"), review_18m)
      assert %{status: :meets, target_text: "43"} = above
      assert GoalStatus.summary(above) == "18-month target 43 · Meets target"

      assert %{status: :meets} = GoalStatus.evaluate(ctx.metric, exact("43"), review_18m)
      assert %{status: :below} = GoalStatus.evaluate(ctx.metric, exact("42"), review_18m)

      assert %{status: :meets, target_text: "51"} =
               GoalStatus.evaluate(ctx.metric, exact("51"), review_36m)

      assert %{status: :below} = GoalStatus.evaluate(ctx.metric, exact("50.5"), review_36m)
    end

    test "lower-is-better metrics still meet at or below the target", ctx do
      review_18m = period!(ctx.org, "review_18m")
      # G2-M2 Novice: 18-month target 39%.
      assert %{status: :meets} = GoalStatus.evaluate(ctx.lower, exact("0.39"), review_18m)
      assert %{status: :meets} = GoalStatus.evaluate(ctx.lower, exact("0.3"), review_18m)
      assert %{status: :below} = GoalStatus.evaluate(ctx.lower, exact("0.4"), review_18m)
    end

    test "missing results and seasonal periods stay neutral", ctx do
      status = GoalStatus.evaluate(ctx.metric, nil, period!(ctx.org, "review_18m"))
      assert %{status: :neutral} = status
      assert GoalStatus.summary(status) == "18-month target 43 · Not compared: no result reported"

      assert %{status: :neutral, reason: :no_target_due} =
               GoalStatus.evaluate(ctx.metric, exact("99"), period!(ctx.org, "fal_26"))
    end
  end

  describe "a review result from a published ND Insights value" do
    setup do
      org = seeded_organization!()
      file = synthetic_file!()

      # Synthetic rows (test database only), shaped like published Growth
      # Rate rows: two years of All Grades and one grade row that must not be used.
      for {year, subject, grade, value} <- [
            {"2023-2024", "ELA", "All Grades", "25"},
            {"2024-2025", "ELA", "All Grades", "38"},
            {"2024-2025", "ELA", "7", "60"}
          ] do
        growth_row!(file, year, subject, grade, value)
      end

      %{org: org, contributor: contributor!(org), metric: metric!(org, "G2-M3")}
    end

    defp synthetic_file! do
      Ash.Seed.seed!(SourceFile, %{
        dataset: :growth_rate,
        file_name: "SYNTHETIC_growth_test.csv",
        sha256: "synthetic-#{System.unique_integer([:positive])}",
        publication_version: "test"
      })
    end

    defp growth_row!(file, year, subject, grade, value) do
      Ash.Seed.seed!(StateResult, %{
        dataset: :growth_rate,
        academic_year: year,
        institution_id: @fort_yates,
        subject: subject,
        grade: grade,
        subgroup: "All",
        measure: "OverallGrowthPercentile",
        unit: :percentile,
        value_state: :exact,
        value: Decimal.new(value),
        natural_key:
          "synthetic|#{year}|#{subject}|#{grade}|#{System.unique_integer([:positive])}",
        publication_version: "test",
        source_file_id: file.id
      })
    end

    defp record_published(ctx, metric, period_code, year) do
      Ash.create(
        ActualResult,
        %{
          metric_id: metric.id,
          reporting_period_id: period!(ctx.org, period_code).id,
          source_year: year
        },
        action: :record_published,
        tenant: ctx.org.id,
        actor: ctx.contributor
      )
    end

    test "uses the All Grades OverallGrowthPercentile for the chosen year with provenance", ctx do
      assert {:ok, entry} = record_published(ctx, ctx.metric, "review_18m", "2024-2025")
      assert entry.source == :nd_insights
      # The All Grades row, not grade 7 (60).
      assert Decimal.equal?(entry.value, "38")
      assert GrowthPercentile.source_year(entry) == "2024-2025"
      assert entry.source_ref =~ "All Grades · All students · OverallGrowthPercentile"
      assert entry.source_ref =~ "SYNTHETIC_growth_test.csv"
      assert entry.author_id == ctx.contributor.id

      # 38 against the 18-month target 43.
      assert %{status: :below} =
               GoalStatus.evaluate(ctx.metric, entry, period!(ctx.org, "review_18m"))
    end

    test "no year is preferred or refused by rule; whichever year is chosen is used", ctx do
      assert {:ok, entry} = record_published(ctx, ctx.metric, "review_36m", "2023-2024")
      assert Decimal.equal?(entry.value, "25")
      assert GrowthPercentile.source_year(entry) == "2023-2024"
    end

    test "the year is required and must have a published value", ctx do
      assert {:error, error} = record_published(ctx, ctx.metric, "review_18m", nil)
      assert :source_year in error_fields(error)

      assert {:error, error} = record_published(ctx, ctx.metric, "review_18m", "2026-2027")
      assert :source_year in error_fields(error)
    end

    test "nothing is recorded at a review until someone saves a chosen year", ctx do
      metric_id = ctx.metric.id

      assert [] =
               ActualResult
               |> Ash.Query.filter(metric_id == ^metric_id)
               |> Ash.read!(tenant: ctx.org.id, authorize?: false)
    end

    test "never into a seasonal period, and never for an unmapped metric", ctx do
      assert {:error, error} = record_published(ctx, ctx.metric, "fal_26", "2024-2025")
      assert :reporting_period_id in error_fields(error)

      assert {:error, error} =
               record_published(ctx, metric!(ctx.org, "G2-M1"), "review_18m", "2024-2025")

      assert :metric_id in error_fields(error)

      # Engagement metrics keep their unconfirmed mapping.
      assert GrowthPercentile.mapping(metric!(ctx.org, "G4-M2")) == nil
    end

    test "viewers cannot record a published value", ctx do
      viewer = user!(ctx.org, :school_leader)
      membership!(viewer, school!(ctx.org), :viewer, ctx.org)

      assert {:error, %Ash.Error.Forbidden{}} =
               record_published(
                 %{ctx | contributor: viewer},
                 ctx.metric,
                 "review_18m",
                 "2024-2025"
               )
    end
  end
end
