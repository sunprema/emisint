defmodule EmisintWeb.Improvement.OberonLiveTest do
  @moduledoc """
  Oberon on the shared ND FIRST School Dashboard: school tabs, its own
  targets and comparisons, and isolation from Fort Yates (updates, history,
  PDF and imports stay with the selected school).
  """
  use EmisintWeb.ConnCase, async: true

  import Emisint.ImprovementFixtures
  import Emisint.NdInsightsFixtures
  import Phoenix.LiveViewTest

  require Ash.Query

  alias Emisint.Improvement.{ActualResult, Metric, ReportingPeriod, Seeds}
  alias Emisint.NdInsights.StateResult
  alias Emisint.Reports.School.NdFirstSchoolPdf

  @fixtures Path.expand("../../../fixtures/nd_insights/oberon", __DIR__)
  @oberon "/school-goals/oberon-elementary"
  @fort_yates "/school-goals/fort-yates-ms"

  setup do
    org =
      seeded_organization!(
        name: "Two ND First schools",
        schools: [Seeds.FortYates, Seeds.Oberon],
        workbook_ratings?: true
      )

    oberon_contributor = user!(org, :school_leader)
    membership!(oberon_contributor, school!(org, "oberon-elementary"), :contributor, org)

    %{
      org: org,
      admin: user!(org, :emo_admin),
      oberon_contributor: oberon_contributor,
      fort_yates_contributor: contributor!(org)
    }
  end

  defp import_oberon!(org) do
    import_insights!(Path.wildcard(Path.join(@fixtures, "*.csv")),
      institution_ids: ["0301662261"],
      tenant: org.id
    )
  end

  defp metric(org, slug, code) do
    school = school!(org, slug)

    Metric
    |> Ash.Query.filter(code == ^code and goal.goal_plan.school_id == ^school.id)
    |> Ash.read_one!(tenant: org.id, authorize?: false)
  end

  defp actuals(org, metric) do
    ActualResult
    |> Ash.Query.filter(metric_id == ^metric.id)
    |> Ash.read!(tenant: org.id, authorize?: false)
  end

  describe "school tabs" do
    test "each enabled school has its own tab and URL; others are coming soon", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} = live(log_in(conn, admin), @oberon)

      assert has_element?(view, "#nd-first-school-tabs", "ND FIRST School Dashboard")
      assert has_element?(view, ~s(#nd-tab-oberon-elementary[aria-current="page"]), "Oberon")
      assert has_element?(view, ~s(#nd-tab-fort-yates-ms[href="#{@fort_yates}"]), "Fort Yates")
      refute has_element?(view, ~s(#nd-tab-fort-yates-ms[aria-current]))

      for name <- ~w(drayton dunseith mandaree valley-middle-school warwick) do
        assert has_element?(view, ~s(#nd-tab-soon-#{name}[aria-disabled="true"]), "Coming soon")
      end

      refute has_element?(view, ~s(#nd-first-school-tabs a[href*="valley"]))
      refute has_element?(view, "#nd-first-school-tabs a", "Cannon Ball")

      {:ok, fort_yates, _html} = live(log_in(conn, admin), @fort_yates)
      assert has_element?(fort_yates, ~s(#nd-tab-fort-yates-ms[aria-current="page"]))
    end

    test "switching schools shows each school's own goals and targets", %{
      conn: conn,
      admin: admin
    } do
      {:ok, oberon, _html} = live(log_in(conn, admin), "#{@oberon}?period=review_18m")

      assert has_element?(oberon, "h1", "Oberon Elementary School")
      assert has_element?(oberon, "#metric-G1-M1", "Increase Proficient & Advanced ELA Data")
      assert has_element?(oberon, "#metric-G1-M1 [data-target-value]", "23%")
      assert has_element?(oberon, "#metric-G3-M1", "Average attendance percentage")
      refute render(oberon) =~ "Fort Yates Middle School will"

      assert {:error, {:live_redirect, %{to: @fort_yates}}} =
               oberon |> element("#nd-tab-fort-yates-ms") |> render_click()

      {:ok, fort_yates, _html} = live(log_in(conn, admin), @fort_yates)

      assert has_element?(fort_yates, "h1", "Fort Yates Middle School")
      assert has_element?(fort_yates, "#metric-G2-M3", "Overall growth percentile (ELA)")
      refute render(fort_yates) =~ "Oberon Elementary School will"
    end
  end

  describe "state results" do
    test "Oberon's own comparisons at both reference checkpoints", %{
      conn: conn,
      org: org,
      admin: admin
    } do
      import_oberon!(org)

      for {ref, novice, committed} <- [{"18m", "29%", "55-60%"}, {"36m", "22%", "60-65%"}] do
        {:ok, view, _html} =
          live(log_in(conn, admin), "#{@oberon}?state_year=2023-2024&goal_ref=#{ref}")

        novice_cell = ~s([data-goal][data-kind="workbook"][data-status="gray"])
        assert has_element?(view, novice_cell, "G1-M2 ELA Novice")
        assert has_element?(view, novice_cell, "target #{novice}")
        assert has_element?(view, novice_cell, "Gray: assessment type unconfirmed")

        assert has_element?(view, ~s([data-goal][data-kind="annual"][data-status="overlaps"]))
        assert has_element?(view, "#engagement-engagement_emotional", "target #{committed}")
        assert has_element?(view, "#engagement-engagement_emotional", "Gray: target is a range")
        assert has_element?(view, "#achievement-matching-note", "G1-M1 and G2-M1")
        assert has_element?(view, "#growth-matching-note", "no growth metric")
        refute has_element?(view, "#achievement-type-note")
        refute render(view) =~ "Combined assessment assumed"
      end
    end

    test "annual targets cover Oberon's historical goal period", %{
      conn: conn,
      org: org,
      admin: admin
    } do
      import_oberon!(org)
      {:ok, view, _html} = live(log_in(conn, admin), @oberon)

      assert has_element?(view, "#annual-goal-period", "2018-19 through 2023-24")
      assert has_element?(view, "#annual-2018-2019-ela", "No result imported")
      assert has_element?(view, "#annual-2023-2024-ela", "Range overlaps target")
      refute has_element?(view, "#annual-goals", "different measure from the workbook")
    end
  end

  describe "isolation" do
    test "an Oberon update is saved to Oberon's metric only, with its own history", %{
      conn: conn,
      org: org,
      oberon_contributor: user
    } do
      {:ok, view, _html} = live(log_in(conn, user), "#{@oberon}?period=fal_26")
      view |> element("#update-G1-M1") |> render_click()

      view
      |> form("#actual-form",
        actual: %{value_state: "exact", value: "21", measurement_date: "2026-10-15"}
      )
      |> render_submit()

      assert has_element?(view, "#actual-G1-M1", "21%")

      oberon_metric = metric(org, "oberon-elementary", "G1-M1")
      fort_yates_metric = metric(org, "fort-yates-ms", "G1-M1")

      assert [entry] = actuals(org, oberon_metric)

      period =
        Ash.get!(ReportingPeriod, entry.reporting_period_id, tenant: org.id, authorize?: false)

      assert period.code == "fal_26"
      assert Decimal.equal?(entry.value, "0.21")
      assert actuals(org, fort_yates_metric) == []

      {:ok, history, _html} = live(log_in(conn, user), "#{@oberon}/metrics/G1-M1")
      assert has_element?(history, "h1", "Increase Proficient & Advanced ELA Data")
      assert has_element?(history, ~s(a[href="#{@oberon}"]), "Oberon Elementary School")
      assert render(history) =~ "21%"
    end

    test "a Fort Yates contributor can't open Oberon, and vice versa", %{
      conn: conn,
      oberon_contributor: oberon_user,
      fort_yates_contributor: fort_yates_user
    } do
      assert {:error, {:live_redirect, %{to: "/school-goals"}}} =
               live(log_in(conn, fort_yates_user), @oberon)

      assert {:error, {:live_redirect, %{to: "/school-goals"}}} =
               live(log_in(conn, oberon_user), @fort_yates)

      {:ok, landing, _html} = live(log_in(conn, oberon_user), "/school-goals")
      assert has_element?(landing, "#school-oberon-elementary")
      refute has_element?(landing, "#school-fort-yates-ms")
    end

    test "another organization's Oberon has its own records", %{
      conn: conn,
      org: org,
      oberon_contributor: user
    } do
      {:ok, view, _html} = live(log_in(conn, user), "#{@oberon}?period=fal_26")
      view |> element("#update-G1-M1") |> render_click()

      view
      |> form("#actual-form",
        actual: %{value_state: "exact", value: "21", measurement_date: "2026-10-15"}
      )
      |> render_submit()

      other = seeded_organization!(name: "Other org", schools: [Seeds.Oberon])
      outsider = user!(other, :emo_admin)

      {:ok, theirs, _html} = live(log_in(conn, outsider), "#{@oberon}?period=fal_26")
      assert has_element?(theirs, "#actual-G1-M1", "Not reported")
      refute has_element?(theirs, "#actual-G1-M1", "21%")
      # Fort Yates isn't seeded there, so its tab leads nowhere for them.
      assert {:error, {:live_redirect, %{to: "/school-goals"}}} =
               live(log_in(conn, outsider), @fort_yates)

      assert [_] = actuals(org, metric(org, "oberon-elementary", "G1-M1"))
      assert actuals(other, metric(other, "oberon-elementary", "G1-M1")) == []
    end
  end

  describe "PDF" do
    test "Oberon's PDF uses Oberon's goals, notes and unconfigured payment", %{
      org: org,
      admin: admin
    } do
      import_oberon!(org)
      scope = %Emisint.Scope{current_user: admin, current_tenant: org.id}

      for ref <- ~w(18m 36m) do
        {:ok, data, _} =
          NdFirstSchoolPdf.build(scope, "oberon-elementary", %{
            "period" => "review_18m",
            "state_year" => "2023-2024",
            "goal_ref" => ref
          })

        assert data.school.name == "Oberon Elementary School"
        assert Enum.map(data.goals, & &1.title) |> hd() == "Goal 1: Literacy Growth"
        assert data.payment.label == "Estimated payment — not configured"
        assert data.payment.combined == "Not configured"
        assert data.payment.card_note =~ "No payment terms are set"
        assert data.state.notes.engagement_matching =~ "G4-M1, G4-M2 and G4-M3"
        assert data.state.notes.growth_matching =~ "no growth metric"

        text = inspect(data)
        assert text =~ "Oberon Goals"
        refute text =~ "Ft Yates Goals"
        refute text =~ "$35,000"
        refute text =~ "Combined assessment assumed"
      end
    end
  end

  describe "imports" do
    test "the Oberon import page is locked to Oberon and stores only Oberon rows", %{
      conn: conn,
      org: org
    } do
      sysadmin = user!(nil, :system_admin)

      {:ok, view, _html} =
        live(log_in(conn, sysadmin, %{"admin_org_id" => org.id}), "#{@oberon}/import")

      assert has_element?(view, "#nd-locked-school", "0301662261")
      assert has_element?(view, ~s(#nd-back-to-school[href="#{@oberon}"]))

      # Importing twice creates the rows once, for Oberon only.
      import_oberon!(org)
      import_oberon!(org)

      ids =
        StateResult
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.institution_id)
        |> Enum.uniq()

      assert ids == ["0301662261"]
      assert StateResult |> Ash.read!(authorize?: false) |> length() == 48 + 24
    end
  end
end
