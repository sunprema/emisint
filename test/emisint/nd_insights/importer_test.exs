defmodule Emisint.NdInsights.ImporterTest do
  use Emisint.DataCase, async: true

  import Emisint.ImprovementFixtures

  require Ash.Query

  alias Emisint.Improvement.{ActualResult, ImplementationRating}
  alias Emisint.NdInsights.{Importer, SchoolResults, SourceFile, StateResult}

  @fixtures Path.expand("../../fixtures/nd_insights", __DIR__)
  @fort_yates "4300429212"
  @performance "Insights-AssessmentPerformance-CSV-2024-2025-v20251113.csv"

  defp fixture(name), do: Path.join(@fixtures, name)

  defp import!(files, ids \\ [@fort_yates]) do
    {:ok, reports} =
      Importer.import_files(Enum.map(List.wrap(files), &fixture/1), institution_ids: ids)

    reports
  end

  defp results(filters \\ []) do
    StateResult |> Ash.Query.filter(^filters) |> Ash.read!(authorize?: false)
  end

  # A copy of the 2024-25 file republished under a new version with one value changed.
  defp republished(version, fun) do
    dir = Path.join(System.tmp_dir!(), "nd-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    path = Path.join(dir, String.replace(@performance, "v20251113", "v#{version}"))
    File.write!(path, fun.(File.read!(fixture(@performance))))
    path
  end

  test "requires explicit institutions" do
    assert {:error, _} = Importer.import_files([fixture(@performance)], institution_ids: [])
  end

  test "imports Fort Yates rows with provenance and registers the source file once" do
    assert [report] = import!(@performance)
    assert report.created == 144
    assert report.unchanged == 0
    assert report.conflict_count == 0
    assert report.publication_version == "20251113"

    assert [file] = Ash.read!(SourceFile, authorize?: false)
    assert file.file_name == @performance
    assert file.dataset == :assessment_performance
    assert file.sha256 == report.sha256
    assert file.import_count == 1
    assert file.last_report["created"] == 144

    assert Enum.all?(
             results(),
             &(&1.source_file_id == file.id and &1.publication_version == "20251113")
           )
  end

  test "re-importing the same file creates nothing and reports everything unchanged" do
    import!(@performance)
    assert [again] = import!(@performance)
    assert again.created == 0
    assert again.unchanged == 144
    assert length(results()) == 144
    assert [%{import_count: 2}] = Ash.read!(SourceFile, authorize?: false)
  end

  test "identical repeated rows are stored once; differing repeats are conflicts and not imported" do
    [report] =
      import!("Insights-AssessmentPerformance-CSV-2099-2100-v20990101.csv", ["TEST000001"])

    # Math / All Grades appears twice with identical values: stored once.
    assert report.duplicate_count == 4
    assert length(results(subject: "Math", grade: "All Grades")) == 4

    # Math / grade 7 is published under two names with different values: neither imported.
    assert report.conflict_count == 4
    assert Enum.all?(report.conflicts, &(&1.reason =~ "none imported"))
    assert results(subject: "Math", grade: "7") == []

    # Grade 8 has an out-of-range Novice value: reported, not clamped.
    assert report.parse_error_count == 1
  end

  test "a newer publication is stored alongside the old one and changes are reported" do
    import!(@performance)

    # In the republished copy, Reading All Grades All Comp Partially moves from 0.3–0.39 to 0.4–0.49.
    path =
      republished("20260101", fn csv ->
        String.replace(
          csv,
          "2024-2025,Fort Yates Middle School,4300429212,All Grades,Reading,Comp,All,All,0.4,0.49,0.3,0.39,",
          "2024-2025,Fort Yates Middle School,4300429212,All Grades,Reading,Comp,All,All,0.4,0.49,0.4,0.49,"
        )
      end)

    {:ok, [report]} = Importer.import_files([path], institution_ids: [@fort_yates])
    assert report.created == 144
    assert report.changed_from_previous_count == 1
    assert [%{previous_version: "20251113"}] = report.changed_from_previous

    # Both publications are kept; the latest is what the school view uses.
    assert length(
             results(
               measure: "Partially",
               subject: "Reading",
               grade: "All Grades",
               subgroup: "All",
               assessment_type: "Comp"
             )
           ) == 2

    latest = SchoolResults.load(user!(nil, :system_admin), @fort_yates)

    [row] =
      SchoolResults.performance(latest.rows, "2024-2025", "Comp", "All")
      |> Enum.filter(&(&1.subject == "Reading" and &1.grade == "All Grades"))

    assert Decimal.equal?(row.levels["Partially"].range_low, "0.4")
  end

  test "a stored value that differs for the same publication is a conflict and is not overwritten" do
    import!(@performance)

    [stored] =
      results(
        measure: "Advanced",
        subject: "Math",
        grade: "All Grades",
        subgroup: "All",
        assessment_type: "Comp"
      )

    Ash.Seed.update!(stored, %{range_high: Decimal.new("0.15")})

    assert [report] = import!(@performance)
    assert report.conflict_count == 1
    assert [%{reason: reason}] = report.conflicts
    assert reason =~ "not overwritten"

    assert Decimal.equal?(Ash.get!(StateResult, stored.id, authorize?: false).range_high, "0.15")
  end

  test "school matching is by InstitutionID; a differing Emisint name is reported, never used to link" do
    org = organization!()

    Ash.create!(
      Emisint.Accounts.School,
      %{name: "Ft Yates MS", slug: "fy", state: "ND", state_entity_id: @fort_yates},
      tenant: org.id,
      authorize?: false
    )

    assert [report] = import!(@performance)

    assert [%{published_name: "Fort Yates Middle School", emisint_school_name: "Ft Yates MS"}] =
             report.name_mismatches

    assert report.created == 144
  end

  test "imports never touch school-entered actual results or ratings" do
    org = seeded_organization!(workbook_ratings?: true)
    contributor = contributor!(org)

    Ash.create!(
      ActualResult,
      %{
        metric_id: metric!(org, "G2-M1").id,
        reporting_period_id: period!(org, "fal_26").id,
        value_state: :exact,
        value: Decimal.new("0.25"),
        measurement_date: ~D[2026-10-15]
      },
      action: :record,
      tenant: org.id,
      actor: contributor
    )

    before =
      {Ash.read!(ActualResult, tenant: org.id, authorize?: false),
       Ash.read!(ImplementationRating, tenant: org.id, authorize?: false)}

    import!([@performance, "Insights-GrowthRate-CSV-2024-2025-v20251113.csv"])

    assert {Ash.read!(ActualResult, tenant: org.id, authorize?: false),
            Ash.read!(ImplementationRating, tenant: org.id, authorize?: false)} ==
             before
  end

  describe "permissions" do
    setup do
      import!(@performance)
      :ok
    end

    test "any signed-in user can read state results; anonymous reads see nothing" do
      org = organization!()
      assert length(Ash.read!(StateResult, actor: user!(org, :school_leader))) == 144
      assert {:ok, []} = Ash.read(StateResult, actor: nil)
    end

    test "only system admins may write state results directly" do
      [row] =
        results(
          measure: "Novice",
          subject: "Math",
          grade: "6",
          subgroup: "All",
          assessment_type: "Comp"
        )

      attrs =
        row
        |> Map.take(
          StateResult.dimensions() ++
            [
              :unit,
              :value_state,
              :value,
              :range_low,
              :range_high,
              :source_text,
              :natural_key,
              :source_file_id
            ]
        )
        |> Map.put(:publication_version, "forged")

      org = organization!()

      for actor <- [user!(org, :emo_admin), user!(org, :school_leader)] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 Ash.create(StateResult, attrs, action: :import, actor: actor)
      end

      assert {:ok, _} =
               Ash.create(StateResult, attrs, action: :import, actor: user!(nil, :system_admin))
    end
  end
end
