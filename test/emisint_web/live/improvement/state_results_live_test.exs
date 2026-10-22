defmodule EmisintWeb.Improvement.StateResultsLiveTest do
  use EmisintWeb.ConnCase, async: true

  import Emisint.ImprovementFixtures
  import Phoenix.LiveViewTest

  require Ash.Query

  alias Emisint.NdInsights.Importer

  @fixtures Path.expand("../../../fixtures/nd_insights", __DIR__)
  @dashboard "/school-goals/fort-yates-ms"

  defp import_fort_yates! do
    files = ~w(
      Insights-AssessmentPerformance-CSV-2023-2024-v20240824.csv
      Insights-AssessmentPerformance-CSV-2024-2025-v20251113.csv
      Insights-AssessmentParticipation-CSV-2024-2025-v20251113.csv
      Insights-GrowthRate-CSV-2024-2025-v20251113.csv
      Insights-Engagement-Emotional-All-CSV-v20251202.csv
      Insights-Engagement-Participation-All-CSV-v20251202.csv
    )

    {:ok, _} =
      Importer.import_files(Enum.map(files, &Path.join(@fixtures, &1)),
        institution_ids: ["4300429212"]
      )
  end

  setup do
    org = seeded_organization!(workbook_ratings?: true)
    viewer = user!(org, :school_leader)
    membership!(viewer, school!(org), :viewer, org)
    %{org: org, viewer: viewer}
  end

  test "without imported data the section says so", %{conn: conn, viewer: viewer} do
    {:ok, view, _html} = live(log_in(conn, viewer), @dashboard)
    assert has_element?(view, "#state-results-empty")
    assert has_element?(view, "#annual-2025-2026-ela", "Not yet published")
  end

  describe "with Fort Yates data imported" do
    setup do
      import_fort_yates!()
      :ok
    end

    test "shows the latest year with published levels, Proficient alone and the derived measure",
         %{conn: conn, viewer: viewer} do
      {:ok, view, _html} = live(log_in(conn, viewer), @dashboard)

      assert has_element?(view, ~s(#state_year option[selected][value="2024-2025"]))
      assert has_element?(view, "#state-achievement th", "Approaching Proficiency")
      assert has_element?(view, "#state-achievement", "Partially")

      row = "#achievement-reading-all-grades"
      # Novice 40%–49%, Approaching 30%–39%, Proficient 20%–29%, Advanced 0%–10%
      assert has_element?(view, row, "40%–49%")
      assert has_element?(view, row, "30%–39%")
      assert has_element?(view, row, "20%–29%")
      assert has_element?(view, row, "0%–10%")
      # Derived Proficient or Advanced 20%–39%; tested 90%–100%
      assert has_element?(view, row, "20%–39%")
      assert has_element?(view, "#achievement-reading-all-grades td:last-child", "%")
    end

    test "groups the state did not publish show “Not published”, never zero", %{
      conn: conn,
      viewer: viewer
    } do
      {:ok, view, _html} = live(log_in(conn, viewer), @dashboard)
      # Grade 5 has no Fort Yates rows in the 2024-25 download, and grade 6 has
      # achievement but no growth rows: nothing is shown for them, not zeros.
      refute has_element?(view, "#achievement-reading-5")
      assert has_element?(view, "#achievement-reading-6")
      refute has_element?(view, "#growth-ela-6")

      # Participation was only imported for 2024-25, so 2023-24 "Tested" is not published.
      {:ok, view, _html} = live(log_in(conn, viewer), "#{@dashboard}?state_year=2023-2024")
      assert has_element?(view, "#achievement-reading-all-grades td:last-child", "Not published")
      refute has_element?(view, "#achievement-reading-all-grades td:last-child", "0%")
    end

    test "academic year selection is independent of the seasonal period", %{
      conn: conn,
      viewer: viewer
    } do
      {:ok, view, _html} = live(log_in(conn, viewer), "#{@dashboard}?period=spr_26")

      view
      |> form("#state-filters",
        state_year: "2023-2024",
        state_type: "Comp",
        state_subgroup: "All"
      )
      |> render_change()

      assert_patch(
        view,
        "#{@dashboard}?period=spr_26&state_subgroup=All&state_type=Comp&state_year=2023-2024"
      )

      assert has_element?(view, "#state-achievement h3", "2023-2024")
      assert has_element?(view, "#period option[selected][value=spr_26]")
      # Seasonal ratings and the payment card are unchanged by state data.
      assert has_element?(view, "#rating-G1-M1", "Some Progress")
      assert has_element?(view, "#payment-card", "Awaiting review")
    end

    test "annual goals compare only with matching published results", %{
      conn: conn,
      viewer: viewer
    } do
      {:ok, view, _html} = live(log_in(conn, viewer), @dashboard)

      # Goals start in 2025-2026 and the latest published year is 2024-2025.
      for year <- ~w(2025-2026 2026-2027 2030-2031), subject <- ~w(ela math) do
        assert has_element?(view, "#annual-#{year}-#{subject}", "Not yet published")
      end

      refute has_element?(view, "#annual-goals", "Meets goal")
      refute has_element?(view, "#annual-goals", "Below goal")
    end

    test "survey participation is shown separately from the engagement categories", %{
      conn: conn,
      viewer: viewer
    } do
      {:ok, view, _html} = live(log_in(conn, viewer), @dashboard)

      refute has_element?(view, "#engagement-engagement_participation")
      refute has_element?(view, "#state-engagement table", "Survey participation")

      # 2024-25: published as 0.95-1.00 on each of the three source rows.
      assert has_element?(view, "#survey-participation", "95%–100%")
      assert has_element?(view, "#survey-participation", "of enrolled students took the survey")
      assert has_element?(view, "#survey-participation", "3 source records, kept separately")

      # The three source rows remain distinct records.
      source_rows =
        Emisint.NdInsights.StateResult
        |> Ash.Query.filter(dataset == :engagement_participation and academic_year == "2024-2025")
        |> Ash.read!(authorize?: false)

      assert source_rows |> Enum.map(& &1.engagement_level) |> Enum.sort() ==
               ~w(Committed Compliant Disengaged)
    end

    test "filter scope is stated for each section", %{conn: conn, viewer: viewer} do
      {:ok, view, _html} =
        live(log_in(conn, viewer), "#{@dashboard}?state_type=Reg&state_subgroup=Female")

      assert has_element?(view, "#state-type-scope", "Achievement and % tested")
      assert has_element?(view, "#state-subgroup-scope", "Achievement and growth")
      assert has_element?(view, "#state-filters", "Engagement Survey is shown for all students")

      assert has_element?(view, "#state-achievement-scope", "Standard assessment · Female")
      assert has_element?(view, "#state-growth-scope", "Female")
      assert has_element?(view, "#state-growth-scope", "assessment type filter does not apply")
      assert has_element?(view, "#state-engagement-scope", "All students")
      refute has_element?(view, "#state-engagement-scope", "Female")
    end

    test "growth, engagement and source files are shown with source links", %{
      conn: conn,
      viewer: viewer
    } do
      {:ok, view, _html} = live(log_in(conn, viewer), @dashboard)

      assert has_element?(view, "#growth-ela-7", "35")
      assert has_element?(view, "#engagement-engagement_emotional", "30%–34%")

      # File names, versions and hashes are collapsed under "Data sources".
      assert has_element?(view, "#state-source-files-toggle[aria-expanded=false]", "Data sources")

      assert has_element?(
               view,
               "#state-source-files.hidden",
               "Insights-AssessmentPerformance-CSV-2024-2025-v20251113.csv"
             )

      assert has_element?(view, "#state-source-files.hidden", "20251113")
      assert has_element?(view, "#state-source-files.hidden", "sha256")

      assert has_element?(
               view,
               ~s(#state-results a[href="https://insights.nd.gov/Education/School/StateAssessment/StudentAchievement/4300429212"])
             )

      assert has_element?(view, ~s(#state-results a[href="https://insights.nd.gov/Data"]))
    end

    test "users without access to the school still cannot open it", %{conn: conn, org: org} do
      outsider = user!(org, :school_leader)

      assert {:error, {:live_redirect, %{to: "/school-goals"}}} =
               live(log_in(conn, outsider), @dashboard)
    end
  end
end
