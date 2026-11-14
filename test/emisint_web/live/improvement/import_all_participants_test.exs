defmodule EmisintWeb.Improvement.ImportAllParticipantsTest do
  @moduledoc """
  The ND Insights import (November 10, 2026) is offered from every supported
  ND First dashboard: the eight participants (Fort Yates, Oberon, Valley
  Middle, Drayton, Dunseith, Mandaree, Warwick, Cannon Ball) and the nine
  district buildings, through the one shared import page.

  Checks that the button is in the same place on every page for system
  admins only, that the import page names the record it is locked to, and
  that importing for one InstitutionID never imports or changes another's
  rows (district vs building, building vs building, and Cannon Ball vs the
  Solen district and Solen High rows in the same file).
  """
  # Never concurrent with other ND Insights imports (see Emisint.NdInsightsFixtures).
  use EmisintWeb.ConnCase, async: true, group: :nd_insights_import

  import Emisint.ImprovementFixtures
  import Emisint.NdInsightsFixtures
  import Phoenix.LiveViewTest

  require Ash.Query

  alias Emisint.Improvement.{Pilot, Seeds}
  alias Emisint.NdInsights.StateResult

  @fixtures Path.expand("../../../fixtures/nd_insights", __DIR__)
  @performance "Insights-AssessmentPerformance-CSV-2024-2025-v20251113.csv"
  @expansion_file Path.join([@fixtures, "expansion", @performance])
  @cannon_ball_file Path.join([@fixtures, "cannon_ball", @performance])

  @fields [
    :id,
    :dataset,
    :academic_year,
    :institution_id,
    :institution_name,
    :subject,
    :grade,
    :assessment_type,
    :subgroup,
    :measure,
    :unit,
    :value_state,
    :value,
    :range_low,
    :range_high,
    :natural_key,
    :publication_version,
    :imported_at
  ]

  setup %{conn: conn} do
    org =
      seeded_organization!(name: "ND First all participants", schools: Seeds.available_schools())

    sysadmin = user!(nil, :system_admin)

    %{
      org: org,
      sysadmin: sysadmin,
      admin_conn: log_in(conn, sysadmin, %{"admin_org_id" => org.id})
    }
  end

  defp upload(view, path) do
    name = Path.basename(path)

    view
    |> file_input("#nd-upload-form", :csv, [
      %{name: name, content: File.read!(path), type: "text/csv"}
    ])
    |> render_upload(name)

    render_async(view, 10_000)
  end

  defp import_now(view, forged_ids) do
    render_change(view, "select", %{"institution_ids" => forged_ids})
    render_submit(view, "import", %{"institution_ids" => forged_ids})
    render_async(view, 10_000)
  end

  defp rows(id) do
    StateResult
    |> Ash.Query.filter(institution_id == ^id)
    |> Ash.read!(authorize?: false)
    |> Enum.map(&Map.take(&1, @fields))
    |> Enum.sort_by(& &1.id)
  end

  # Measures the file publishes for `id` (the parser the importer uses).
  defp measures(path, id) do
    {:ok, parsed} =
      Emisint.NdInsights.Parser.parse_file(path,
        institution_ids: [id],
        file_name: Path.basename(path)
      )

    length(parsed.observations)
  end

  defp stored_ids,
    do:
      StateResult
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.institution_id)
      |> Enum.uniq()
      |> Enum.sort()

  describe "where the import is offered" do
    test "every seeded ND First record is a supported import target" do
      ids = Enum.map(Seeds.available_schools(), & &1.school().state_entity_id)

      # 8 participants + 9 district buildings + Solen High School (Cannon Ball's building).
      assert length(ids) == 18
      assert Enum.sort(ids) == Enum.sort(Pilot.institution_ids())
      assert length(Pilot.roster()) == 8
      assert Enum.all?(Pilot.roster(), & &1.enabled?)
    end

    test "every participant and building dashboard has the button in the same place, and its page names the record",
         %{admin_conn: conn} do
      for module <- Seeds.available_schools() do
        %{name: name, slug: slug, state_entity_id: id} = module.school()
        {:ok, dashboard, _html} = live(conn, "/school-goals/#{slug}")

        assert has_element?(
                 dashboard,
                 ~s(#state-results #nd-import-link[href="/school-goals/#{slug}/import"]),
                 "Import ND Insights data"
               ),
               slug

        {:ok, page, _html} = live(conn, "/school-goals/#{slug}/import")
        assert has_element?(page, "#nd-locked-school-name", name), slug
        assert has_element?(page, "#nd-locked-school-id", id), slug
        assert has_element?(page, ~s(#nd-back-to-school[href="/school-goals/#{slug}"])), slug

        kind =
          cond do
            module == Seeds.CannonBall -> "School"
            function_exported?(module, :buildings, 0) -> "District"
            function_exported?(module, :participant, 0) -> "Building"
            true -> "School"
          end

        assert has_element?(page, "#nd-locked-school-kind", kind), slug
        assert has_element?(page, "#nd-locked-scope-note", "InstitutionID #{id}"), slug
      end
    end

    test "district and building pages list each other's separate InstitutionIDs", %{
      admin_conn: conn
    } do
      {:ok, district, _} = live(conn, "/school-goals/drayton-public-school-district/import")

      assert has_element?(
               district,
               "#nd-locked-scope-note",
               "Drayton Elementary School (3401919281)"
             )

      assert has_element?(district, "#nd-locked-scope-note", "(3401919283)")

      {:ok, building, _} = live(conn, "/school-goals/drayton-high-school/import")
      assert has_element?(building, "#nd-locked-school-kind", "Building")
      assert has_element?(building, "#nd-locked-school", "of Drayton")
      assert has_element?(building, "#nd-locked-scope-note", "(34019)")
      assert has_element?(building, "#nd-locked-scope-note", "(3401919281)")

      assert building |> element("#nd-locked-scope-note") |> render() =~
               "Only rows published under InstitutionID 3401919283 are imported. These related records have their own InstitutionIDs and are imported only from their own pages: Drayton Public School District (34019); Drayton Elementary School (3401919281)."

      {:ok, cannon_ball, _} = live(conn, "/school-goals/cannon-ball-elementary/import")
      assert has_element?(cannon_ball, "#nd-locked-school-kind", "School")

      note = cannon_ball |> element("#nd-locked-scope-note") |> render()
      assert note =~ "Only rows published under InstitutionID 4300312781 are imported."
      assert note =~ "imported only from their own pages: Solen High School (4300380363)."

      {:ok, solen, _} = live(conn, "/school-goals/solen-high-school/import")
      assert has_element?(solen, "#nd-locked-school-kind", "Building")
      assert has_element?(solen, "#nd-locked-school", "of Cannon Ball")

      assert has_element?(
               solen,
               "#nd-locked-scope-note",
               "Cannon Ball Elementary School (4300312781)"
             )
    end

    test "organization admins, contributors and viewers get no button and no import page", %{
      org: org,
      conn: base_conn
    } do
      emo_admin = user!(org, :emo_admin)
      contributor = user!(org, :school_leader)
      viewer = user!(org, :school_leader)
      membership!(contributor, school!(org, "drayton-public-school-district"), :contributor, org)
      membership!(viewer, school!(org, "cannon-ball-elementary"), :viewer, org)
      membership!(viewer, school!(org, "warwick-high-school"), :viewer, org)

      cases =
        [{emo_admin, Enum.map(Seeds.available_schools(), & &1.school().slug)}] ++
          [
            {contributor, ["drayton-public-school-district"]},
            {viewer, ["cannon-ball-elementary", "warwick-high-school"]}
          ]

      for {user, slugs} <- cases, slug <- slugs do
        conn = log_in(base_conn, user)
        {:ok, dashboard, _} = live(conn, "/school-goals/#{slug}")
        assert has_element?(dashboard, "#state-results"), slug
        refute has_element?(dashboard, "#nd-import-link"), slug

        assert {:error, {:live_redirect, %{to: "/school-goals", flash: flash}}} =
                 live(conn, "/school-goals/#{slug}/import")

        assert flash["error"] =~ "Only system admins", slug
      end
    end
  end

  describe "recent imports on a record's page" do
    test "Drayton High keeps its history when more than 25 newer runs belong to other records",
         %{admin_conn: conn} do
      log = fn ids, name ->
        Emisint.NdInsights.ImportRun
        |> Ash.Changeset.for_create(
          :log,
          %{outcome: :no_changes, file_name: name, institution_ids: ids},
          authorize?: false
        )
        |> Ash.create!(authorize?: false)
      end

      own = log.(["3401919283", "99999"], "drayton-high-history.csv")
      others = for n <- 1..30, do: log.(["34019"], "district-only-#{n}.csv")
      elementary = log.(["3401919281"], "elementary-only.csv")

      {:ok, view, _html} = live(conn, "/school-goals/drayton-high-school/import")
      assert has_element?(view, "#nd-import-runs #run-#{own.id}", "drayton-high-history.csv")
      refute has_element?(view, "#nd-import-runs", "No imports yet.")

      for run <- [elementary | others],
          do: refute(has_element?(view, "#nd-import-runs #run-#{run.id}"))

      {:ok, district, _html} = live(conn, "/school-goals/drayton-public-school-district/import")
      assert has_element?(district, "#nd-import-runs #run-#{List.last(others).id}")
      refute has_element?(district, "#nd-import-runs #run-#{own.id}")
      refute has_element?(district, "#nd-import-runs #run-#{elementary.id}")
    end
  end

  describe "importing for one record never changes another" do
    test "a district import stores only district rows; building rows stay as they were", %{
      admin_conn: conn
    } do
      # Drayton Elementary's rows were already imported from its own page.
      import_insights!([@expansion_file], institution_ids: ["3401919281"])
      elementary_before = rows("3401919281")
      assert elementary_before != []

      {:ok, view, _} = live(conn, "/school-goals/drayton-public-school-district/import")
      upload(view, @expansion_file)

      # The statewide-style file has the district, both buildings and Valley.
      assert has_element?(view, "#nd-school-34019 input[checked][disabled]")

      for other <- ~w(3401919281 3401919283 1800189752),
          do: refute(has_element?(view, "#nd-school-#{other}"))

      # Forged selections of the buildings are ignored.
      n = measures(@expansion_file, "34019")
      assert n > 0
      import_now(view, ["3401919281", "3401919283", "1800189752"])
      assert has_element?(view, "#nd-result", "#{n} new")

      assert stored_ids() == ["34019", "3401919281"]
      assert length(rows("34019")) == n
      assert rows("3401919281") == elementary_before

      # Importing again creates nothing and still leaves the building alone.
      upload(view, @expansion_file)
      assert has_element?(view, "#nd-already-imported")
      import_now(view, [])
      assert has_element?(view, "#nd-result", "0 new · #{n} already stored")
      assert rows("3401919281") == elementary_before
      assert stored_ids() == ["34019", "3401919281"]
    end

    test "a building import stores only that building; the district and the other building are unchanged",
         %{admin_conn: conn} do
      import_insights!([@expansion_file], institution_ids: ["34019", "3401919281"])
      district_before = rows("34019")
      elementary_before = rows("3401919281")

      {:ok, view, _} = live(conn, "/school-goals/drayton-high-school/import")
      upload(view, @expansion_file)
      assert has_element?(view, "#nd-pilot-scope", "Locked to Drayton High School")
      refute has_element?(view, "#nd-school-34019")
      refute has_element?(view, "#nd-school-3401919281")

      n = measures(@expansion_file, "3401919283")
      assert n > 0
      import_now(view, ["34019", "3401919281"])
      assert has_element?(view, "#nd-result", "#{n} new")

      assert length(rows("3401919283")) == n
      assert rows("34019") == district_before
      assert rows("3401919281") == elementary_before
      assert stored_ids() == ["34019", "3401919281", "3401919283"]
    end

    test "Cannon Ball imports only 4300312781, never the Solen district or Solen High rows", %{
      admin_conn: conn
    } do
      {:ok, view, _} = live(conn, "/school-goals/cannon-ball-elementary/import")
      upload(view, @cannon_ball_file)

      assert has_element?(view, "#nd-school-4300312781 input[checked][disabled]")
      refute has_element?(view, "#nd-school-43003")
      refute has_element?(view, "#nd-school-4300380363")

      n = measures(@cannon_ball_file, "4300312781")
      assert n > 0
      import_now(view, ["43003", "4300380363"])
      assert has_element?(view, "#nd-result", "#{n} new")
      assert stored_ids() == ["4300312781"]
    end
  end
end
