defmodule EmisintWeb.Improvement.ExpansionSchoolsTest do
  @moduledoc """
  The remaining supported ND First participants (November 8, 2026): Valley
  Middle School (one building) and the district participants Drayton,
  Dunseith, Mandaree and Warwick (`Seeds.Participant`).

  Checks that each record holds only its own sources (workbook goals on the
  participant, PDF annual targets on each building), that seeds are rerun-safe,
  that each dashboard and PDF shows only its own InstitutionID's published
  rows, and that school and organization permissions hold.

  Fixtures in `expansion/` are rows for Drayton (34019), Drayton Elementary
  (3401919281), Drayton High (3401919283) and Valley Middle (1800189752),
  copied unchanged from the official 2024-25 Performance, Participation and
  Growth files and the Emotional Engagement file.
  """
  # Never concurrent with other ND Insights imports (see Emisint.NdInsightsFixtures).
  use EmisintWeb.ConnCase, async: true, group: :nd_insights_import

  import Emisint.ImprovementFixtures
  import Emisint.NdInsightsFixtures
  import Phoenix.LiveViewTest

  require Ash.Query

  alias Emisint.Accounts.School
  alias Emisint.Improvement.{AnnualAssessmentGoal, Goal, GoalPlan, Metric, ResultGoals, Seeds}
  alias Emisint.Improvement.Seeds.Participant
  alias Emisint.Reports.School.NdFirstSchoolPdf

  @fixtures Path.expand("../../../fixtures/nd_insights/expansion", __DIR__)

  @new_modules [
    Seeds.ValleyMiddle,
    Seeds.Drayton,
    Seeds.DraytonElementary,
    Seeds.DraytonHigh,
    Seeds.Dunseith,
    Seeds.DunseithElementary,
    Seeds.DunseithHigh,
    Seeds.Mandaree,
    Seeds.MandareeElementary,
    Seeds.MandareeHigh,
    Seeds.Warwick,
    Seeds.WarwickElementary,
    Seeds.WarwickMiddle,
    Seeds.WarwickHigh
  ]

  @district "/school-goals/drayton-public-school-district"
  @elementary "/school-goals/drayton-elementary"
  @high "/school-goals/drayton-high-school"
  @valley "/school-goals/valley-middle-school"

  setup do
    org =
      seeded_organization!(
        name: "ND First expansion",
        schools: @new_modules,
        workbook_ratings?: true
      )

    import_insights!(Path.wildcard(Path.join(@fixtures, "*.csv")),
      institution_ids: ["34019", "3401919281", "3401919283", "1800189752"],
      tenant: org.id
    )

    %{org: org, admin: user!(org, :emo_admin)}
  end

  defp counts(org, slug) do
    school = school!(org, slug)

    plan =
      GoalPlan
      |> Ash.Query.filter(school_id == ^school.id)
      |> Ash.read_one!(tenant: org.id, authorize?: false)

    read = fn resource, filter ->
      resource |> Ash.Query.filter(^filter) |> Ash.read!(tenant: org.id, authorize?: false)
    end

    %{
      plan: plan,
      goals: length(read.(Goal, goal_plan_id: plan.id)),
      metrics: read.(Metric, goal_plan_id: plan.id) |> Map.new(&{&1.code, &1}),
      ratings:
        Emisint.Improvement.ImplementationRating
        |> Ash.Query.filter(school_id == ^school.id)
        |> Ash.read!(tenant: org.id, authorize?: false)
        |> length(),
      annual:
        read.(AnnualAssessmentGoal, school_id: school.id)
        |> Map.new(&{{&1.school_year, &1.subject}, Decimal.to_string(&1.target_value, :normal)})
    }
  end

  describe "definitions" do
    test "district participants hold the workbook goals and no annual targets", %{org: org} do
      for {slug, goals, metrics, ratings} <- [
            {"drayton-public-school-district", 5, 13, 26},
            {"dunseith-public-school-district", 6, 16, 32},
            {"mandaree-public-school-district", 6, 6, 12},
            {"warwick-public-school-district", 5, 25, 50}
          ] do
        c = counts(org, slug)
        assert {c.goals, map_size(c.metrics), c.ratings} == {goals, metrics, ratings}, slug
        assert c.annual == %{}, slug
        assert c.plan.payment_cap == Decimal.new("70000")
        # The workbook's 18-month terms (November 13, 2026); the 36-month allocation is unset.
        assert c.plan.payment_terms_status == :provisional
        assert c.plan.allocation_18m == Decimal.new("70000")
        assert c.plan.allocation_36m == nil
      end

      # Values cite their own cells and keep text verbatim.
      d = counts(org, "drayton-public-school-district").metrics
      assert d["G1-M1"].baseline_value == Decimal.new("0.27")
      assert d["G1-M1"].source_values["baseline"]["cell"] == "Drayton Goals!D4"
      assert d["G4-M1"].target_36m == nil
      assert d["G4-M1"].source_values["target_36m"]["raw"] == "< 18%"

      du = counts(org, "dunseith-public-school-district").metrics
      assert du["G1-M2"].source_values["target_18m"]["raw"] == "50% K-6; 100% 7-12"
      assert :value_as_text in du["G1-M2"].flags

      w = counts(org, "warwick-public-school-district").metrics
      assert w["G2-M6"].baseline_value == Decimal.new("0.2574")
      assert w["G2-M6"].source_values["target_18m"]["raw"] == "Dec 2-3%"
      assert w["G2-M6"].target_18m == nil

      m = counts(org, "mandaree-public-school-district").metrics
      assert m["G3-M1"].source_values["baseline"]["raw"] == "< 2.4"
    end

    test "buildings hold only their own PDF annual targets", %{org: org} do
      expected = %{
        "drayton-elementary" => {{"0.21", "0.31"}, {"0.45", "0.52"}},
        "drayton-high-school" => {{"0.2", "0.19"}, {"0.44", "0.43"}},
        "dunseith-elementary" => {{"0.26", "0.24"}, {"0.48", "0.46"}},
        "dunseith-high-school" => {{"0.17", "0.25"}, {"0.41", "0.47"}},
        "mandaree-elementary" => {{"0.2", "0.11"}, {"0.44", "0.37"}},
        "mandaree-high-school" => {{"0.35", "0.16"}, {"0.54", "0.4"}},
        "warwick-elementary" => {{"0.06", "0.1"}, {"0.33", "0.37"}},
        "warwick-middle-school" => {{"0.12", "0.08"}, {"0.38", "0.35"}},
        "warwick-high-school" => {{"0.15", "0.31"}, {"0.4", "0.52"}}
      }

      for {slug, {{ela1, math1}, {ela6, math6}}} <- expected do
        c = counts(org, slug)
        assert {c.goals, map_size(c.metrics), c.ratings} == {0, 0, 0}, slug
        assert map_size(c.annual) == 12, slug
        assert c.annual[{"2025-2026", :ela}] == ela1, slug
        assert c.annual[{"2025-2026", :math}] == math1, slug
        assert c.annual[{"2030-2031", :ela}] == ela6, slug
        assert c.annual[{"2030-2031", :math}] == math6, slug
        assert c.plan.payment_cap == nil
      end

      valley = counts(org, "valley-middle-school")
      assert {valley.goals, map_size(valley.metrics), valley.ratings} == {7, 26, 52}
      assert valley.annual[{"2025-2026", :ela}] == "0.37"
      assert valley.annual[{"2030-2031", :math}] == "0.51"
    end

    test "seeding again creates nothing and reports no drift", %{org: org} do
      {:ok, report} = Seeds.run(org.id, schools: @new_modules, workbook_ratings?: true)
      assert report.created == []
      assert report.drift == []
      assert report.unchanged != []
    end

    test "workbook mappings are the confirmed or provisional ones, none a candidate, and scopes are explicit" do
      # User decisions of November 12, 2026.
      expected = %{
        Seeds.ValleyMiddle => {~w(G3-M1 G5-M2), :confirmations},
        Seeds.Drayton => {~w(G4-M1 G4-M2), :confirmations},
        Seeds.Dunseith => {~w(G6-M2), :confirmations},
        Seeds.Warwick => {~w(G2-M6 G3-M1 G3-M2 G4-M1 G4-M2), :provisional}
      }

      for module <- @new_modules do
        config = ResultGoals.config(module.school())
        codes = Enum.map(config.workbook, &elem(&1, 0))
        {want, key} = Map.get(expected, module, {[], :confirmations})

        assert codes == want, inspect(module)
        assert config.candidates == %{}, inspect(module)
        assert Enum.sort(Map.keys(Map.fetch!(config, key))) == Enum.sort(codes), inspect(module)
      end

      assert %{kind: :participant, buildings: [Seeds.DraytonElementary, Seeds.DraytonHigh]} =
               Participant.scope(Seeds.Drayton.school())

      assert %{kind: :building, participant: Seeds.Warwick} =
               Participant.scope(Seeds.WarwickMiddle.school())

      assert %{kind: :school} = Participant.scope(Seeds.ValleyMiddle.school())
    end
  end

  describe "dashboards" do
    test "the district shows workbook goals and only the district's own rows", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} =
        live(log_in(conn, admin), "#{@district}?state_year=2024-2025&state_type=Comp")

      assert has_element?(view, ~s(#nd-tab-drayton-public-school-district[aria-current="page"]))
      assert has_element?(view, "#participant-scope", "District participant")
      assert has_element?(view, "#related-drayton-elementary", "Drayton Elementary School")
      assert has_element?(view, "#related-drayton-high-school", "Drayton High School")
      assert has_element?(view, "#goals")
      assert has_element?(view, "#metric-G1-M1")

      assert has_element?(
               view,
               "#payment-summary",
               "36-month review payment allocation needs confirmation"
             )

      assert has_element?(view, "#annual-by-building", "Drayton Elementary School")

      # District 34019: Approaching Proficiency 50%–54% (the elementary publishes 55%–59%).
      assert has_element?(view, "#achievement-reading-all-grades", "50%–54%")
      refute has_element?(view, "#achievement-reading-all-grades", "55%–59%")
      assert has_element?(view, "#engagement-engagement_emotional", "30%–34%")
      refute has_element?(view, "[data-goal][data-kind=workbook]")
    end

    test "a building shows its own targets and rows, without workbook goals or payment", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} =
        live(log_in(conn, admin), "#{@high}?state_year=2024-2025&state_type=Comp")

      assert has_element?(view, ~s(#nd-tab-drayton-public-school-district[aria-current="page"]))
      assert has_element?(view, "#building-scope", "Drayton Public School District")
      refute has_element?(view, "#goals")
      refute has_element?(view, "#payment-card")
      refute has_element?(view, "#payment")
      refute has_element?(view, "#period")

      assert has_element?(view, "#annual-2025-2026", "20%")

      assert has_element?(
               view,
               "#annual-2025-2026-ela",
               "No matching results in the imported data"
             )

      # Drayton High School's own 2024-25 rows; it publishes no growth rows.
      assert has_element?(view, "#achievement-reading-all-grades", "30%–39%")
      assert has_element?(view, "#achievement-reading-all-grades", "70%–79%")
      assert has_element?(view, "#growth-empty")
      assert has_element?(view, "#engagement-engagement_emotional", "15%–19%")

      {:ok, elementary, _html} =
        live(log_in(conn, admin), "#{@elementary}?state_year=2024-2025&state_type=Comp")

      assert has_element?(elementary, "#achievement-reading-all-grades", "55%–59%")
      assert has_element?(elementary, "#annual-2025-2026", "21%")
      assert has_element?(elementary, "#annual-2025-2026", "31%")
    end

    test "Valley shows its workbook goals, its annual targets and its own rows", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} =
        live(log_in(conn, admin), "#{@valley}?state_year=2024-2025&state_type=Comp")

      assert has_element?(view, ~s(#nd-tab-valley-middle-school[aria-current="page"]))
      refute has_element?(view, "#participant-scope")
      refute has_element?(view, "#building-scope")
      assert has_element?(view, "#metric-G3-M1")
      assert has_element?(view, "#annual-goal-period", "2025-2026 through 2030-2031")

      assert has_element?(
               view,
               "#annual-2025-2026-ela",
               "No matching results in the imported data"
             )

      assert has_element?(view, "#achievement-matching-note", "No workbook goal is matched")
      # Exact published values for Valley 2024-25 (Reading, Combined, all students).
      assert has_element?(view, "#achievement-reading-all-grades", "25%")
      refute has_element?(view, "[data-goal][data-kind=workbook]")
    end
  end

  describe "permissions" do
    test "a building membership doesn't open the district or another building", %{
      conn: conn,
      org: org
    } do
      viewer = user!(org, :school_leader)
      membership!(viewer, school!(org, "drayton-elementary"), :viewer, org)

      {:ok, view, _html} = live(log_in(conn, viewer), @elementary)
      # The district is named, not linked, and isn't a navigation destination.
      assert has_element?(
               view,
               ~s(#related-drayton-public-school-district[data-readable="false"])
             )

      refute has_element?(view, ~s(a#related-drayton-public-school-district))
      refute has_element?(view, "#participant-nav-drayton-public-school-district")

      for path <- [@district, @high, "#{@district}/report.pdf"] do
        assert {:error, {_, %{to: "/school-goals"}}} =
                 conn |> log_in(viewer) |> get_or_live(path)
      end
    end

    test "another organization's admin can't open these records", %{conn: conn} do
      other = organization!("Another org")
      outsider = user!(other, :emo_admin)

      for path <- [@district, @elementary, @valley] do
        assert {:error, {_, %{to: "/school-goals"}}} = live(log_in(conn, outsider), path)
      end
    end
  end

  # LiveView pages redirect with {:error, {:live_redirect | :redirect, ...}};
  # the PDF controller redirects with a 302.
  defp get_or_live(conn, path) do
    if String.ends_with?(path, ".pdf") do
      conn = get(conn, path)

      if conn.status == 302,
        do: {:error, {:redirect, %{to: redirected_to(conn)}}},
        else: {:ok, conn}
    else
      live(conn, path)
    end
  end

  describe "PDF" do
    test "district and building reports keep their scopes and render", %{org: org, admin: admin} do
      scope = %Emisint.Scope{current_user: admin, current_tenant: org.id}
      params = %{"state_year" => "2024-2025", "state_type" => "Comp"}

      {:ok, district, _} = NdFirstSchoolPdf.build(scope, "drayton-public-school-district", params)
      assert district.scope.kind == "participant"
      assert district.scope.note =~ "Drayton Elementary School, Drayton High School"
      assert length(district.goals) == 5
      assert district.annual == []
      assert district.scope.annual_empty =~ "per building"

      {:ok, building, _} = NdFirstSchoolPdf.build(scope, "drayton-high-school", params)
      assert building.scope.kind == "building"
      assert building.goals == []
      assert length(building.annual) == 6

      refute Enum.any?(
               building.guidance,
               &String.starts_with?(&1, ["Goal tables", "Estimated payment"])
             )

      refute inspect(building) =~ "Drayton Goals!"

      for slug <- ~w(drayton-public-school-district drayton-high-school valley-middle-school) do
        assert {:ok, "%PDF" <> _, _} = NdFirstSchoolPdf.generate(scope, slug, params)
      end
    end
  end

  test "School records aren't duplicated across scopes", %{org: org} do
    slugs = School |> Ash.read!(tenant: org.id, authorize?: false) |> Enum.map(& &1.slug)
    assert length(slugs) == length(Enum.uniq(slugs))
    assert length(slugs) == length(@new_modules)
  end
end
