defmodule EmisintWeb.Improvement.OberonMissingResultsTest do
  @moduledoc """
  Regression coverage for Oberon (0301662261) years without published
  achievement or growth rows (November 8, 2026):

    * the Student Group select always shows the active selection (including
      "All students") and is disabled when only one group is offered;
    * % tested stays visible when achievement levels are missing, and the
      year's Engagement Survey results still appear;
    * a missing table explains itself and links to the latest imported year
      with matching results, changing only the year, and only on click;
    * nothing is filled in for the missing results, and Fort Yates is
      unchanged.

  Fixtures in `oberon_missing_years/` are Oberon's rows copied unchanged
  from the official 2023-24 and 2024-25 Participation and 2023-24 Growth
  downloads. The official 2024-25 Performance and Growth downloads have no
  Oberon rows.
  """
  # Never concurrent with other ND Insights imports (see Emisint.NdInsightsFixtures).
  use EmisintWeb.ConnCase, async: true, group: :nd_insights_import

  import Emisint.ImprovementFixtures
  import Emisint.NdInsightsFixtures
  import Phoenix.LiveViewTest

  alias Emisint.Improvement.Seeds
  alias Emisint.NdInsights.SchoolResults
  alias Emisint.Reports.School.NdFirstSchoolPdf

  @root Path.expand("../../../fixtures/nd_insights", __DIR__)
  @oberon_fixtures [Path.join(@root, "oberon"), Path.join(@root, "oberon_missing_years")]
  @oberon "/school-goals/oberon-elementary"
  @fort_yates "/school-goals/fort-yates-ms"

  setup do
    org =
      seeded_organization!(
        name: "Two ND First schools",
        schools: [Seeds.FortYates, Seeds.Oberon],
        workbook_ratings?: true
      )

    import_insights!(Enum.flat_map(@oberon_fixtures, &Path.wildcard(Path.join(&1, "*.csv"))),
      institution_ids: ["0301662261"],
      tenant: org.id
    )

    %{org: org, admin: user!(org, :emo_admin)}
  end

  defp import_fort_yates!(org) do
    import_insights!(
      Enum.map(
        ~w(Insights-AssessmentPerformance-CSV-2024-2025-v20251113.csv
           Insights-AssessmentParticipation-CSV-2024-2025-v20251113.csv
           Insights-GrowthRate-CSV-2024-2025-v20251113.csv),
        &Path.join(@root, &1)
      ),
      institution_ids: ["4300429212"],
      tenant: org.id
    )
  end

  defp selected_group(view, value, label),
    do: has_element?(view, ~s(#state_subgroup option[value="#{value}"][selected]), label)

  describe "student group select" do
    test "shows All students as the active selection and lists published groups", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} =
        live(log_in(conn, admin), "#{@oberon}?state_year=2024-2025&state_type=Comp")

      assert selected_group(view, "All", "All students")
      # 2024-25 publishes % tested for Female and Male (no achievement or growth).
      assert has_element?(view, ~s(#state_subgroup option[value="Female"]))
      assert has_element?(view, ~s(#state_subgroup option[value="Male"]))
      refute has_element?(view, "#state_subgroup[disabled]")
      refute has_element?(view, "#state-subgroup-only")
    end

    test "is disabled, still showing All students, when it is the only group", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} =
        live(log_in(conn, admin), "#{@oberon}?state_year=2024-2025&state_type=Alt")

      assert has_element?(view, "#state_subgroup[disabled]")
      assert selected_group(view, "All", "All students")
      assert has_element?(view, ~s(#state_subgroup option), "All students")
      refute has_element?(view, ~s(#state_subgroup option[value="Female"]))
      assert has_element?(view, "#state-subgroup-only", "Only all students")
    end

    test "follows year and assessment changes, and drops a group that no longer applies", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} =
        live(
          log_in(conn, admin),
          "#{@oberon}?state_year=2023-2024&state_type=Comp&state_subgroup=Female&goal_ref=36m"
        )

      assert selected_group(view, "Female", "Female")

      # Alternate has only "All": the disabled select isn't submitted, so the
      # earlier group is cleared from the URL rather than kept.
      render_change(view, "state_filters", %{
        "state_year" => "2023-2024",
        "state_type" => "Alt",
        "goal_ref" => "36m"
      })

      path = assert_patch(view)
      refute path =~ "state_subgroup"
      assert path =~ "goal_ref=36m"
      assert has_element?(view, "#state_subgroup[disabled]")
      assert selected_group(view, "All", "All students")

      render_change(view, "state_filters", %{
        "state_year" => "2024-2025",
        "state_type" => "Comp",
        "state_subgroup" => "Male",
        "goal_ref" => "36m"
      })

      assert_patch(view)
      refute has_element?(view, "#state_subgroup[disabled]")
      assert selected_group(view, "Male", "Male")
      assert has_element?(view, "#state-achievement-scope", "Combined assessment · Male")
    end
  end

  describe "missing achievement and growth" do
    test "2024-25 shows % tested and engagement without inventing achievement values", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} =
        live(log_in(conn, admin), "#{@oberon}?state_year=2024-2025&state_type=Comp")

      assert has_element?(
               view,
               "#achievement-empty",
               "No published achievement results for Combined assessment · All students · 2024-2025"
             )

      assert has_element?(view, "#achievement-tested-only")

      # Published % tested, as published (official 2024-25 Participation download).
      for {row, tested} <- [
            {"reading-all-grades", "90%–94%"},
            {"math-all-grades", "95%–100%"},
            {"science-all-grades", "80%–100%"}
          ] do
        assert has_element?(view, "#achievement-#{row}", tested)
        assert has_element?(view, "#achievement-#{row}", "Achievement not published")
        # No goal comparison is made for a missing achievement result.
        refute has_element?(view, "#achievement-#{row} [data-goal]")
      end

      assert has_element?(view, "#achievement-math-all-grades", "Meets 95% participation target")

      # Engagement Survey results published for 2024-25 are shown.
      assert has_element?(view, "#engagement-engagement_emotional", "45%–49%")
      assert has_element?(view, "#engagement-engagement_emotional", "10%–14%")
      refute has_element?(view, "#engagement-empty")

      assert has_element?(
               view,
               "#growth-empty",
               "No published growth results for All students · 2024-2025"
             )
    end

    test "links to the latest matching year, keeping the other filters, only on click", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} =
        live(
          log_in(conn, admin),
          "#{@oberon}?period=review_18m&state_year=2024-2025&state_type=Comp&goal_ref=36m"
        )

      for id <- ~w(achievement-latest-year growth-latest-year) do
        assert has_element?(view, ~s(##{id}[data-latest-year="2023-2024"]), "View 2023-2024")
        link = ~s(##{id} a[href*="state_year=2023-2024"])
        assert has_element?(view, link)

        for kept <- ~w(period=review_18m state_type=Comp state_subgroup=All goal_ref=36m) do
          assert has_element?(view, ~s(##{id} a[href*="#{kept}"]))
        end
      end

      # Rendering the link doesn't change the selected year.
      assert has_element?(view, ~s(#state_year option[value="2024-2025"][selected]))

      view |> element("#achievement-latest-year a") |> render_click()
      path = assert_patch(view)

      for kept <- ~w(state_year=2023-2024 period=review_18m state_type=Comp goal_ref=36m) do
        assert path =~ kept
      end

      assert has_element?(view, ~s(#state_year option[value="2023-2024"][selected]))
      refute has_element?(view, "#achievement-empty")
      refute has_element?(view, "#growth-empty")
      assert has_element?(view, "#achievement-reading-all-grades", "50%–59%")
      assert has_element?(view, "#growth-ela-all-grades", "53.5")
    end

    test "the latest year depends on the student group and assessment type", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} =
        live(
          log_in(conn, admin),
          "#{@oberon}?state_year=2024-2025&state_type=Comp&state_subgroup=Female"
        )

      # Female achievement is published for 2023-24; Female growth never is.
      assert has_element?(view, ~s(#achievement-latest-year[data-latest-year="2023-2024"]))
      assert has_element?(view, ~s(#achievement-latest-year a[href*="state_subgroup=Female"]))

      assert has_element?(
               view,
               ~s(#growth-latest-year[data-latest-year="none"]),
               "No imported year"
             )

      {:ok, view, _html} =
        live(log_in(conn, admin), "#{@oberon}?state_year=2024-2025&state_type=Alt")

      assert has_element?(view, ~s(#achievement-latest-year[data-latest-year="none"]))
      assert has_element?(view, "#state-achievement", "Try Combined or Standard")
    end

    test "Fort Yates rows never supply Oberon's latest year, and Fort Yates is unchanged", %{
      conn: conn,
      org: org,
      admin: admin
    } do
      import_fort_yates!(org)

      {:ok, oberon, _html} =
        live(log_in(conn, admin), "#{@oberon}?state_year=2024-2025&state_type=Comp")

      assert has_element?(oberon, "#achievement-empty")
      assert has_element?(oberon, ~s(#achievement-latest-year[data-latest-year="2023-2024"]))

      {:ok, fort_yates, _html} = live(log_in(conn, admin), @fort_yates)

      refute has_element?(fort_yates, "#achievement-empty")
      refute has_element?(fort_yates, "#growth-empty")
      refute has_element?(fort_yates, "#achievement-latest-year")
      refute has_element?(fort_yates, "[data-achievement=not-published]")
      refute has_element?(fort_yates, "#state_subgroup[disabled]")
      assert selected_group(fort_yates, "All", "All students")
      assert has_element?(fort_yates, ~s(#state_subgroup option[value="Female"]))
      assert has_element?(fort_yates, "#achievement-reading-all-grades", "95%–97%")
      refute has_element?(fort_yates, "#state-results", "Oberon")
    end
  end

  describe "PDF" do
    test "2024-25 lists % tested and names the latest matching year; 2023-24 is complete", %{
      org: org,
      admin: admin
    } do
      scope = %Emisint.Scope{current_user: admin, current_tenant: org.id}

      {:ok, data, _} =
        NdFirstSchoolPdf.build(scope, "oberon-elementary", %{
          "state_year" => "2024-2025",
          "state_type" => "Comp"
        })

      assert data.report.state_subgroup == "All students"

      assert Enum.map(data.state.achievement, & &1.subject) == [
               "ELA (Reading)",
               "Math",
               "Science"
             ]

      reading = hd(data.state.achievement)
      assert inspect(reading.tested) =~ "90%–94%"

      for key <- ~w(novice partially proficient advanced derived)a do
        assert inspect(Map.fetch!(reading, key)) =~ "Not published"
      end

      assert data.state.achievement_empty =~ "No published achievement results"
      assert data.state.achievement_empty =~ "% tested is shown"

      assert data.state.achievement_empty =~
               "Latest imported year with achievement results for the same filters: 2023-2024."

      assert data.state.growth == []

      assert data.state.growth_empty =~
               "Latest imported year with growth results for the same filters: 2023-2024."

      # The fixtures carry the Emotional engagement file (all years), so its
      # 2024-25 row is listed; engagement is never hidden by missing achievement.
      assert [%{area: "Emotional"}] = data.state.engagement

      {:ok, data, _} =
        NdFirstSchoolPdf.build(scope, "oberon-elementary", %{
          "state_year" => "2023-2024",
          "state_type" => "Comp"
        })

      assert data.state.achievement_empty == ""
      assert length(data.state.growth) == 2
    end
  end

  describe "SchoolResults" do
    defp row(attrs) do
      Map.merge(
        %{
          academic_year: "2024-2025",
          assessment_type: "Comp",
          subgroup: "All",
          accommodations: "All",
          subject: "Reading",
          grade: "All Grades",
          measure: "PercentTested",
          dataset: :assessment_participation
        },
        Map.new(attrs)
      )
    end

    test "subgroups always offer All first and follow the assessment type" do
      rows = [
        row(subgroup: "Female"),
        row(subgroup: "Male", assessment_type: "Reg"),
        row(dataset: :growth_rate, subgroup: "Homeless", assessment_type: nil, measure: "Meets")
      ]

      assert SchoolResults.subgroups(rows, "2024-2025", "Comp") == ["All", "Female", "Homeless"]
      assert SchoolResults.subgroups(rows, "2024-2025", "Reg") == ["All", "Homeless", "Male"]
      assert SchoolResults.subgroups([], "2024-2025", "Alt") == ["All"]
    end

    test "% tested without achievement levels is kept with no levels" do
      [tested] = SchoolResults.performance([row([])], "2024-2025", "Comp", "All")

      assert tested.levels == %{}
      assert tested.tested.measure == "PercentTested"
      assert {:not_derivable, _} = tested.proficient_or_advanced
      refute SchoolResults.achievement_published?([tested])
    end

    test "latest_year_with matches type and group, and returns nil when none" do
      rows = [
        row(dataset: :assessment_performance, measure: "Novice", academic_year: "2022-2023"),
        row(dataset: :assessment_performance, measure: "Novice", academic_year: "2023-2024"),
        row(
          dataset: :assessment_performance,
          measure: "Novice",
          academic_year: "2024-2025",
          subgroup: "Female"
        ),
        row([])
      ]

      filters = %{type: "Comp", subgroup: "All"}
      assert SchoolResults.latest_year_with(rows, :achievement, filters) == "2023-2024"
      assert SchoolResults.latest_year_with(rows, :achievement, %{filters | type: "Alt"}) == nil
      assert SchoolResults.latest_year_with(rows, :growth, filters) == nil
    end
  end
end
