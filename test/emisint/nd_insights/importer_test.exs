defmodule Emisint.NdInsights.ImporterTest do
  use Emisint.DataCase, async: true

  import Emisint.ImprovementFixtures
  import Emisint.NdInsightsFixtures

  require Ash.Query

  alias Emisint.Improvement.{ActualResult, ImplementationRating}
  alias Emisint.NdInsights.{Importer, SchoolResults, SourceFile, StateResult}

  @fixtures Path.expand("../../fixtures/nd_insights", __DIR__)
  @fort_yates "4300429212"
  @performance "Insights-AssessmentPerformance-CSV-2024-2025-v20251113.csv"

  defp fixture(name), do: Path.join(@fixtures, name)

  defp import!(files, ids \\ [@fort_yates]),
    do: import_insights!(Enum.map(List.wrap(files), &fixture/1), institution_ids: ids)

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

  describe "run log and refresh" do
    test "every attempt is logged with user, time and outcome" do
      admin = user!(nil, :system_admin)
      path = fixture(@performance)
      upload_name = Path.basename(path)

      {:ok, _} =
        Importer.import_files([{path, upload_name}], institution_ids: [@fort_yates], actor: admin)

      {:ok, _} =
        Importer.import_files([{path, upload_name}], institution_ids: [@fort_yates], actor: admin)

      {:ok, [failed]} =
        Importer.import_files([{path, "renamed.csv"}], institution_ids: ["NOPE"], actor: admin)

      assert failed.created == 0

      runs = Emisint.NdInsights.list_recent_import_runs!(actor: admin)
      assert Enum.map(runs, & &1.outcome) |> Enum.sort() == [:imported, :no_changes, :no_changes]
      assert Enum.all?(runs, &(&1.imported_by_id == admin.id and &1.ran_at))

      imported = Enum.find(runs, &(&1.outcome == :imported))
      assert imported.file_name == @performance
      assert imported.publication_version == "20251113"
      assert imported.institution_ids == [@fort_yates]
      assert imported.report["created"] == 144
    end

    test "unreadable files are logged as failed" do
      path = Path.join(System.tmp_dir!(), "nd-bad-#{System.unique_integer([:positive])}.csv")
      File.write!(path, "A,B\n1,2\n")
      on_exit(fn -> File.rm(path) end)

      {:ok, [report]} = Importer.import_files([path], institution_ids: [@fort_yates])
      assert report.error =~ "unrecognized columns"

      admin = user!(nil, :system_admin)

      assert [%{outcome: :failed, error: error}] =
               Emisint.NdInsights.list_recent_import_runs!(actor: admin)

      assert error =~ "unrecognized columns"
    end

    test "only system admins can read the run log" do
      import!(@performance)
      org = organization!()

      for actor <- [user!(org, :emo_admin), user!(org, :school_leader)] do
        result = Ash.read(Emisint.NdInsights.ImportRun, action: :recent, actor: actor)
        assert match?({:ok, []}, result) or match?({:error, %Ash.Error.Forbidden{}}, result)
      end
    end

    # A one-row file for a synthetic institution unique to the calling test,
    # so concurrent tests' broadcasts on the shared topic can't interfere.
    defp synthetic_file do
      id = "TEST#{System.unique_integer([:positive])}"
      dir = Path.join(System.tmp_dir!(), "nd-bc-#{id}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)
      path = Path.join(dir, "Insights-AssessmentPerformance-CSV-2099-2100-v20990101.csv")

      File.write!(path, """
      AcademicYear,InstitutionName,InstitutionID,Grade,Subject,AssessmentType,Accomodations,Subgroup,NoviceRangeLow,NoviceRangeHigh,PartiallyRangeLow,PartiallyRangeHigh,ProficientRangeLow,ProficientRangeHigh,AdvancedRangeLow,AdvancedRangeHigh
      2099-2100,Synthetic Broadcast School,#{id},All Grades,Math,Comp,All,All,0.4,0.49,0.3,0.39,0.1,0.19,0,0.1
      """)

      {id, path}
    end

    test "a successful import broadcasts the refreshed institutions" do
      {id, path} = synthetic_file()
      Phoenix.PubSub.subscribe(Emisint.PubSub, Importer.topic())
      {:ok, [_]} = Importer.import_files([path], institution_ids: [id])
      assert_receive {:nd_insights_imported, [^id]}

      # A repeat import changes nothing and broadcasts nothing for this school.
      {:ok, [%{created: 0}]} = Importer.import_files([path], institution_ids: [id])
      refute_receive {:nd_insights_imported, [^id]}
    end

    test "a requested sub-topic receives the broadcast instead of the shared topic" do
      {id, path} = synthetic_file()
      topic = "#{Importer.topic()}:test-#{id}"
      Phoenix.PubSub.subscribe(Emisint.PubSub, topic)
      Phoenix.PubSub.subscribe(Emisint.PubSub, Importer.topic())

      {:ok, [_]} = Importer.import_files([path], institution_ids: [id], topic: topic)

      # Exactly one message: the sub-topic's, not a second one on the shared topic.
      assert_receive {:nd_insights_imported, [^id]}
      refute_receive {:nd_insights_imported, [^id]}
    end

    test "a session topic is honored only inside the ND Insights namespace" do
      sub_topic = "#{Importer.topic()}:test-1"
      assert Importer.topic(%{"nd_insights_topic" => sub_topic}) == sub_topic
      assert Importer.topic(%{"nd_insights_topic" => "users:1"}) == Importer.topic()
      assert Importer.topic(%{"nd_insights_topic" => Importer.topic() <> "x"}) == Importer.topic()
      assert Importer.topic(%{}) == Importer.topic()
    end
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

    # A revision is refused unless explicitly confirmed, and nothing is written.
    {:ok, [refused]} = Importer.import_files([path], institution_ids: [@fort_yates])
    assert refused.error =~ "revised publication (v20260101)"
    assert refused.error =~ "v20251113"
    assert length(results()) == 144

    {:ok, [report]} =
      Importer.import_files([path], institution_ids: [@fort_yates], accept_revisions: true)

    assert report.created == 144
    assert report.prior_versions == ["20251113"]
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

  describe "North Dakota benchmark rows" do
    @state "99999"
    @with_state "with_state/" <> @performance

    test "are stored with the school's and reported separately; a repeat creates nothing" do
      [report] = import!(@with_state, [@fort_yates, @state])

      assert report.by_institution == %{
               @fort_yates => %{created: 144, unchanged: 0},
               @state => %{created: 160, unchanged: 0}
             }

      assert length(results(institution_id: @state)) == 160

      [again] = import!(@with_state, [@fort_yates, @state])
      assert again.created == 0
      assert again.by_institution[@state] == %{created: 0, unchanged: 160}
      assert length(results()) == 304
    end

    test "can be added later from a file already imported for the school, without duplicates" do
      [first] = import!(@with_state)
      assert first.by_institution == %{@fort_yates => %{created: 144, unchanged: 0}}

      [later] = import!(@with_state, [@fort_yates, @state])

      assert later.by_institution == %{
               @fort_yates => %{created: 0, unchanged: 144},
               @state => %{created: 160, unchanged: 0}
             }

      assert length(results(institution_id: @fort_yates)) == 144
    end

    test "SchoolResults loads the latest state rows for one year only" do
      import!(@with_state, [@fort_yates, @state])

      # Public state data: any signed-in user can read it.
      reader = user!(organization!(), :school_leader)
      rows = SchoolResults.load_benchmark(reader, "2024-2025")
      assert length(rows) == 160
      assert Enum.all?(rows, &(&1.institution_id == @state))
      assert SchoolResults.load_benchmark(reader, "2023-2024") == []
    end
  end

  describe "upload preview" do
    alias Emisint.NdInsights.UploadPreview

    setup do
      seeded_organization!(name: "Preview Org")
      :ok
    end

    test "describes the state rows separately from the school" do
      {:ok, preview} =
        UploadPreview.build(fixture("with_state/" <> @performance), @performance,
          institution_ids: [@fort_yates],
          benchmark?: true
        )

      assert [%{institution_id: @fort_yates, measures: 144}] = preview.schools

      assert %{usable?: true, institution_id: "99999", measures: 160, already_stored: 0} =
               preview.benchmark
    end

    test "a school-only file still previews, and says it has no state rows" do
      {:ok, preview} =
        UploadPreview.build(fixture(@performance), @performance,
          institution_ids: [@fort_yates],
          benchmark?: true
        )

      assert [%{measures: 144}] = preview.schools
      assert %{present?: false, usable?: false} = preview.benchmark
    end

    test "ID 99999 under another name is not used as the state benchmark" do
      dir = Path.join(System.tmp_dir!(), "nd-renamed-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)
      path = Path.join(dir, @performance)

      File.write!(
        path,
        fixture("with_state/" <> @performance)
        |> File.read!()
        |> String.replace("State of North Dakota", "Somewhere Else")
      )

      {:ok, preview} =
        UploadPreview.build(path, @performance, institution_ids: [@fort_yates], benchmark?: true)

      assert %{present?: true, usable?: false, published_names: ["Somewhere Else"]} =
               preview.benchmark
    end
  end

  describe "concurrent imports" do
    # Imports are serialized with a transaction-scoped advisory lock taken
    # before any write, so two imports never wait on each other's
    # uncommitted rows (the cause of the intermittent 40P01 deadlocks between
    # async tests, and of a SHA-256 unique violation when the same file was
    # uploaded twice at once). In the SQL sandbox the test's transaction is
    # still open, so the lock taken by the import is visible here.
    test "an import holds the import lock for the rest of its transaction" do
      key = Importer.import_lock_key()

      held = fn ->
        %{rows: [[n]]} =
          Ecto.Adapters.SQL.query!(
            Emisint.Repo,
            "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid() " <>
              "AND classid = $1 AND objid = $2 AND objsubid = 1 AND granted",
            [div(key, 4_294_967_296), rem(key, 4_294_967_296)]
          )

        n
      end

      assert held.() == 0
      import!(@performance)
      assert held.() == 1
    end

    test "a revision check runs after the lock, inside the import transaction" do
      import!(@performance)
      path = republished("20260101", & &1)

      assert {:ok, [%{error: error}]} =
               Importer.import_files([path], institution_ids: [@fort_yates])

      assert error =~ "revised publication"
    end
  end
end
