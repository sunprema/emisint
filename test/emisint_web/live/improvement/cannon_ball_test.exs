defmodule EmisintWeb.Improvement.CannonBallTest do
  @moduledoc """
  Cannon Ball (November 9, 2026): the workbook's "Solen Goals" sheet is the
  Cannon Ball ND FIRST participant (confirmed by the user). Its record is
  Cannon Ball Elementary School (InstitutionID 4300312781, Solen Public School
  District 43003).

  Fixtures in `cannon_ball/` are the rows for Cannon Ball Elementary
  (4300312781), Solen Public School District (43003) and Solen High School
  (4300380363), copied unchanged from the official 2023-24 and 2024-25
  Performance, 2024-25 Participation and Growth files and the Overall
  Engagement file. The Solen rows prove they are never imported or shown for
  Cannon Ball.
  """
  use EmisintWeb.ConnCase, async: true

  import Emisint.ImprovementFixtures
  import Emisint.NdInsightsFixtures
  import Phoenix.LiveViewTest

  require Ash.Query

  alias Emisint.Improvement.{Dashboard, ImplementationRating, Payment, Pilot, Portfolio, Seeds}
  alias Emisint.Improvement.Seeds.CannonBall
  alias Emisint.NdInsights.StateResult
  alias Emisint.Reports.School.NdFirstSchoolPdf

  @fixtures Path.expand("../../../fixtures/nd_insights/cannon_ball", __DIR__)
  @page "/school-goals/cannon-ball-elementary"

  setup do
    org =
      seeded_organization!(
        name: "ND First Cannon Ball",
        schools: Seeds.available_schools(),
        workbook_ratings?: true
      )

    import_cannon_ball!(org)
    %{org: org, admin: user!(org, :emo_admin)}
  end

  defp import_cannon_ball!(org),
    do:
      import_insights!(Path.wildcard(Path.join(@fixtures, "*.csv")),
        institution_ids: ["4300312781"],
        tenant: org.id
      )

  defp scope(user, org), do: %Emisint.Scope{current_user: user, current_tenant: org.id}
  defp metric(code), do: Enum.find(CannonBall.metrics(), &(&1.code == code))

  defp assert_close(%Decimal{} = value, expected) do
    diff = value |> Decimal.sub(Decimal.new(expected)) |> Decimal.abs()
    assert Decimal.compare(diff, Decimal.new("0.000000001")) == :lt, "#{value} != #{expected}"
  end

  describe "definitions" do
    test "the participant mapping and InstitutionID" do
      assert %{state_entity_id: "4300312781", district_name: "Solen Public School District"} =
               CannonBall.school()

      assert CannonBall.participant_mapping().workbook_sheet == "Solen Goals"
      assert CannonBall.participant_mapping().confirmation =~ "Confirmed by the user"
      assert Seeds.module_for("4300312781") == CannonBall
      assert "4300312781" in Pilot.institution_ids()
      # Solen district and Solen High School are not ND First records.
      refute Seeds.module_for("43003")
      refute Seeds.module_for("4300380363")
      assert List.last(Pilot.roster()).name == "Cannon Ball"
    end

    test "goals, metrics, baselines, targets and ratings match the Solen Goals sheet" do
      assert length(CannonBall.goals()) == 7
      metrics = CannonBall.metrics()
      assert length(metrics) == 18
      # Goals Dashboard!C6, D6.
      assert Enum.count(metrics, &(&1.category == :systems)) == 5
      assert Enum.count(metrics, &(&1.category == :student_outcome)) == 13

      g1m1 = metric("G1-M1")
      assert Decimal.equal?(g1m1.baseline_value, "0.11")
      assert Decimal.equal?(g1m1.target_18m, "0.18")
      assert Decimal.equal?(g1m1.target_36m, "0.33")
      assert g1m1.source_values["baseline"] == %{"cell" => "Solen Goals!D4", "raw" => "0.11"}

      assert %{direction: :lower_is_better, unit: :percent} = metric("G1-M4")
      assert %{unit: :count, baseline_value: b} = metric("G4-M1")
      assert Decimal.equal?(b, 5)

      # Dates and text are kept as written, flagged, never coerced.
      g5m1 = metric("G5-M1")
      assert :source_value_is_date in g5m1.flags
      assert g5m1.baseline_value == nil and g5m1.target_18m == nil
      g7m2 = metric("G7-M2")
      assert :value_as_text in g7m2.flags
      assert g7m2.source_values["baseline"]["raw"] == "< 10%"
      # No baseline in the workbook: missing, not zero.
      assert metric("G2-M1").baseline_value == nil

      ratings = CannonBall.workbook_ratings()
      assert length(ratings) == 36
      assert {"G4-M1", "spr_26", 1, "Solen Goals!E26"} in ratings
      assert {"G4-M1", "sum_26", 2, "Solen Goals!F26"} in ratings
    end

    test "annual targets are the PDF's (p.4), each with its stated year" do
      goals = CannonBall.annual_assessment_goals()
      assert length(goals) == 12
      by = Map.new(goals, &{{&1.school_year, &1.subject}, &1.target_value})
      assert Decimal.equal?(by[{"2025-2026", :ela}], "0.13")
      assert Decimal.equal?(by[{"2025-2026", :math}], "0.07")
      assert Decimal.equal?(by[{"2030-2031", :ela}], "0.38")
      assert Decimal.equal?(by[{"2030-2031", :math}], "0.34")
      assert Enum.all?(goals, &(&1.includes_alternate and &1.measure == :proficient_or_advanced))
      assert CannonBall.comparison().annual_years.status == :stated
      assert CannonBall.comparison().workbook == []
    end
  end

  describe "state results" do
    test "only Cannon Ball Elementary's own rows are stored", %{org: org} do
      ids =
        StateResult
        |> Ash.read!(tenant: org.id, authorize?: false)
        |> Enum.map(& &1.institution_id)
        |> Enum.uniq()

      assert ids == ["4300312781"]
    end

    test "seeds and imports rerun without duplicates or overwriting manual entries", %{
      org: org,
      admin: admin
    } do
      {:ok, defs} = Dashboard.load_plan(scope(admin, org), school!(org, "cannon-ball-elementary"))
      fal = Enum.find(defs.periods, &(&1.code == "fal_26"))
      g1m1 = Enum.find(defs.metrics, &(&1.code == "G1-M1"))

      manual =
        Ash.create!(
          ImplementationRating,
          %{metric_id: g1m1.id, reporting_period_id: fal.id, rating_state: :rated, score: 3},
          action: :record,
          tenant: org.id,
          actor: admin
        )

      {:ok, report} =
        Seeds.run(org.id, schools: [CannonBall], workbook_ratings?: true)

      assert report.created == []
      assert report.drift == []

      reports = import_cannon_ball!(org)
      assert Enum.all?(reports, &(&1.created == 0 and &1.conflict_count == 0))

      current =
        Dashboard.current_ratings(scope(admin, org), school!(org, "cannon-ball-elementary"))

      assert current[fal.id][g1m1.id].id == manual.id
      assert current[fal.id][g1m1.id].score == 3
    end
  end

  describe "dashboard and PDF" do
    test "the dashboard shows its goals, ratings, annual targets and own results", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, html} = live(log_in(conn, admin), "#{@page}?period=spr_26&state_year=2024-2025")

      assert has_element?(view, ~s(#nd-tab-cannon-ball-elementary[aria-current="page"]))
      assert has_element?(view, "#metric-G1-M1")
      assert has_element?(view, "#metric-G7-M2")

      assert has_element?(
               view,
               "#annual-2025-2026-ela",
               "No matching results in the imported data"
             )

      assert has_element?(view, "#payment-card", "not configured")
      assert html =~ "Cannon Ball Elementary School"
      # Its own 2024-25 Reading Novice (All Grades, Combined): 55%–59%.
      assert html =~ "55%–59%"
    end

    test "a contributor records and reviews an entry with its history", %{conn: conn, org: org} do
      user = user!(org, :school_leader)
      membership!(user, school!(org, "cannon-ball-elementary"), :contributor, org)

      {:ok, view, _html} = live(log_in(conn, user), "#{@page}?period=fal_26")
      view |> element("#update-G1-M1") |> render_click()

      view
      |> form("#actual-form",
        actual: %{value_state: "exact", value: "21", measurement_date: "2026-10-15"}
      )
      |> render_submit()

      assert has_element?(view, "#actual-G1-M1", "21%")

      {:ok, history, _html} = live(log_in(conn, user), "#{@page}/metrics/G1-M1")
      assert render(history) =~ "21%"
    end

    test "the PDF has Cannon Ball's own goals, targets and results", %{org: org, admin: admin} do
      params = %{"state_year" => "2024-2025", "state_type" => "Comp"}

      {:ok, data, filename} =
        NdFirstSchoolPdf.build(scope(admin, org), "cannon-ball-elementary", params)

      assert filename =~ "cannon-ball"
      assert length(data.goals) == 7
      assert length(data.annual) == 6
      assert data.state.has_data
      # Its own 2024-25 Reading Novice (All Grades, Combined); Solen rows are never imported.
      assert inspect(data) =~ "55%–59%"

      assert {:ok, "%PDF" <> _, _} =
               NdFirstSchoolPdf.generate(scope(admin, org), "cannon-ball-elementary", params)
    end
  end

  describe "portfolio" do
    test "Cannon Ball replaces the Solen placeholder, with the workbook's values", %{
      org: org,
      admin: admin
    } do
      s = Portfolio.summary(scope(admin, org))

      assert Enum.map(s.rows, & &1.slug) == [
               "fort-yates-ms",
               "cannon-ball-elementary",
               "oberon-elementary",
               "warwick-public-school-district",
               "mandaree-public-school-district",
               "dunseith-public-school-district",
               "drayton-public-school-district",
               "valley-middle-school"
             ]

      cb = Enum.find(s.rows, &(&1.slug == "cannon-ball-elementary"))
      assert cb.status == :loaded
      assert cb.name == "Cannon Ball"
      assert cb.workbook_note =~ "Solen"
      # Goals Dashboard!C6:H6.
      assert cb.counts == %{systems: 5, outcomes: 13}
      assert_close(cb.columns.spr_26.systems.value, "1.2")
      assert_close(cb.columns.spr_26.outcomes.value, "1.923076923")
      assert_close(cb.columns.sum_26.systems.value, "1.4")
      assert_close(cb.columns.sum_26.outcomes.value, "1.923076923")

      # Payment: the plan's allocations are not configured.
      assert cb.payment.estimate.status == :no_terms
      assert Payment.status_text(cb.payment.estimate) == "Not configured"

      # AVERAGE row over all 8 participants: C = 68 / 8 = 8.5 (Goals Dashboard!C13).
      assert s.average.participants == 8
      assert Decimal.equal?(s.average.counts.systems.value, "8.5")

      # The workbook's E13 also averages its Example School (E4 = 1.25):
      # (8 participants' mean × 8 + 1.25) / 9 = 1.353927554.
      e = s.average.columns.spr_26.systems.value

      assert_close(
        e
        |> Decimal.mult(8)
        |> Decimal.add(Decimal.new("1.25"))
        |> Decimal.div(9)
        |> Decimal.round(9),
        "1.353927554"
      )
    end
  end

  describe "access" do
    test "a Fort Yates contributor can't open Cannon Ball, and vice versa", %{
      conn: conn,
      org: org
    } do
      fy = user!(org, :school_leader)
      membership!(fy, school!(org, "fort-yates-ms"), :contributor, org)
      cb = user!(org, :school_leader)
      membership!(cb, school!(org, "cannon-ball-elementary"), :viewer, org)

      assert {:error, {:live_redirect, %{to: "/school-goals"}}} = live(log_in(conn, fy), @page)

      assert {:error, {:live_redirect, %{to: "/school-goals"}}} =
               live(log_in(conn, cb), "/school-goals/fort-yates-ms")

      assert Enum.map(Portfolio.summary(scope(cb, org)).rows, & &1.slug) == [
               "cannon-ball-elementary"
             ]
    end
  end
end
