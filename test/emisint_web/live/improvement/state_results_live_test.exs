defmodule EmisintWeb.Improvement.StateResultsLiveTest do
  # Never concurrent with other ND Insights imports (see Emisint.NdInsightsFixtures).
  use EmisintWeb.ConnCase, async: true, group: :nd_insights_import

  import Emisint.NdInsightsFixtures

  import Emisint.ImprovementFixtures
  import Phoenix.LiveViewTest

  require Ash.Query

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

    import_insights!(Enum.map(files, &Path.join(@fixtures, &1)),
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
    assert has_element?(view, "#annual-2025-2026-ela", "No matching results in the imported data")
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
        "#{@dashboard}?goal_ref=18m&period=spr_26&state_subgroup=All&state_type=Comp&state_year=2023-2024"
      )

      assert has_element?(view, "#state-achievement h3", "2023-2024")
      assert has_element?(view, "#period option[selected][value=spr_26]")
      # Seasonal ratings and the payment card are unchanged by state data.
      assert has_element?(view, "#rating-G1-M1", "Some Progress")
      assert has_element?(view, "#payment-combined-text", "Awaiting review")
    end

    test "annual goals compare only with matching published results", %{
      conn: conn,
      viewer: viewer
    } do
      {:ok, view, _html} = live(log_in(conn, viewer), @dashboard)

      # Goals start in 2025-2026 and the latest published year is 2024-2025.
      for year <- ~w(2025-2026 2026-2027 2030-2031), subject <- ~w(ela math) do
        assert has_element?(
                 view,
                 "#annual-#{year}-#{subject}",
                 "No matching results in the imported data"
               )
      end

      refute has_element?(view, "#annual-goals td", "Meets target")
      refute has_element?(view, "#annual-goals td", "Below target")
      # Unpublished results stay uncolored; the key states the shared rule.
      refute has_element?(view, "#annual-goals td [class*=nd-cell-]")
      assert has_element?(view, "#annual-color-key", "same rule as the")
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

    test "a filter combination with no published rows, such as Alternate, says so", %{
      conn: conn,
      viewer: viewer
    } do
      {:ok, view, _html} = live(log_in(conn, viewer), "#{@dashboard}?state_type=Alt")

      assert has_element?(
               view,
               "#achievement-empty",
               "No published achievement results for Alternate assessment · All students · 2024-2025"
             )

      assert has_element?(view, "#state-achievement", "Try Combined or Standard")
      refute has_element?(view, "#achievement-reading-all-grades")
    end

    test "main tables are colored against school goals, never North Dakota",
         %{conn: conn, viewer: viewer} do
      {:ok, view, _html} = live(log_in(conn, viewer), "#{@dashboard}?period=spr_26")

      assert has_element?(view, "#goal-legend", "not an official ND FIRST scoring method")
      assert has_element?(view, "#goal-reference-note", "18-month target as a reference")
      assert has_element?(view, ~s(#goal_ref option[selected][value="18m"]))

      # Section-level notes: the demo assumptions and future targets, once.
      assert has_element?(
               view,
               "#achievement-goal-notes",
               "Reference comparison; Combined assessment assumed for workbook targets."
             )

      assert has_element?(view, "#achievement-goal-notes", "compared against future targets")

      assert has_element?(
               view,
               "#engagement-goal-notes",
               "Reference comparison; schoolwide survey population match assumed."
             )

      # Achievement (2024-25, All Grades) vs the 18-month targets:
      # ELA Novice 40%–49% vs 39%: red; ELA Proficient 20%–29% vs 27%: amber;
      # Math Novice 70%–79% vs 72%: amber; Math Proficient 0%–10% vs 8%: amber.
      ela = "#achievement-reading-all-grades"
      math = "#achievement-math-all-grades"
      assert has_element?(view, "#{ela} td:nth-child(3).nd-cell-error", "Above target")
      assert has_element?(view, "#{ela} td:nth-child(5).nd-cell-warning", "Range overlaps target")

      assert has_element?(
               view,
               "#{ela} td:nth-child(5)",
               "2024-2025 result vs 18-month target 27%"
             )

      assert has_element?(view, "#{math} td:nth-child(3).nd-cell-warning")
      assert has_element?(view, "#{math} td:nth-child(5).nd-cell-warning")
      refute has_element?(view, "#state-achievement", "Intermediate level")

      # Proficient + Advanced: no 2024-25 annual target, none substituted.
      refute has_element?(view, "#{ela} td:nth-child(7) [data-goal]")
      # Grade rows 6–8: the schoolwide target as a reference, never a grade goal.
      assert has_element?(
               view,
               "#achievement-goal-notes",
               "Grade-level colors compare each grade’s results with the schoolwide target for reference. These are not separate grade-level goals."
             )

      ela8 = "#achievement-reading-8 td:nth-child(5)"

      assert has_element?(
               view,
               "#{ela8}.nd-cell-success [data-kind=grade_reference]",
               "At or above schoolwide target"
             )

      assert has_element?(view, ela8, "Schoolwide reference: 27% · 18-month")
      assert has_element?(view, ela8, "40%–49%")

      assert has_element?(
               view,
               "#achievement-reading-7 td:nth-child(3).nd-cell-error",
               "Above schoolwide target"
             )

      assert has_element?(
               view,
               "#achievement-math-6 td:nth-child(3).nd-cell-warning",
               "Range overlaps schoolwide target"
             )

      refute has_element?(view, "#state-achievement", "Meets goal")
      # No targets for Approaching Proficiency, Advanced or Science.
      refute has_element?(view, "#achievement-reading-8 td:nth-child(4) [data-goal]")
      refute has_element?(view, "#achievement-reading-8 td:nth-child(6) [data-goal]")
      refute has_element?(view, "#achievement-science-8 [data-goal]")
      # Growth grade rows: the percentile against the schoolwide target.
      # ELA 7 is 35 (vs 43) and ELA 8 is 64; Math 7 is 58 (vs 46), Math 8 is 41.
      assert has_element?(
               view,
               "#state-growth",
               "Grade-level colors compare each grade’s growth percentile with the schoolwide target for reference. These are not separate grade-level goals."
             )

      assert has_element?(
               view,
               "#growth-ela-7 td:nth-child(9).nd-cell-error",
               "Below schoolwide target"
             )

      assert has_element?(
               view,
               "#growth-ela-7 td:nth-child(9)",
               "Growth percentile target: 43 · 18-month · Schoolwide reference"
             )

      assert has_element?(view, "#growth-ela-8 td:nth-child(9).nd-cell-success", "64")

      assert has_element?(
               view,
               "#growth-math-7 td:nth-child(9).nd-cell-success",
               "At or above schoolwide target"
             )

      assert has_element?(view, "#growth-math-8 td:nth-child(9).nd-cell-error", "41")
      refute has_element?(view, "#growth-ela-7 td:nth-child(5) [data-goal]")

      # Growth percentiles 38 vs 43 and 41 vs 46: red, no percent sign.
      percentile = "#growth-ela-all-grades td:nth-child(9)"
      assert has_element?(view, "#{percentile}.nd-cell-error [data-goal=G2-M3]", "Below target")

      assert has_element?(
               view,
               percentile,
               "2024-2025 result · Growth percentile target: 43 · 18-month"
             )

      assert has_element?(view, "#{percentile} details p", "not an official ND FIRST")
      assert has_element?(view, "#growth-math-all-grades td:nth-child(9).nd-cell-error", "41")

      # Emotional Disengaged 40%–44% vs 32.9%: red; Committed never matched.
      emotional = "#engagement-engagement_emotional"

      assert has_element?(
               view,
               "#{emotional} td:nth-child(4).nd-cell-error [data-goal=G4-M2]",
               "Above target"
             )

      refute has_element?(view, "#{emotional} td:nth-child(2) [data-goal]")

      # % tested: the participation target as a label, never a fill.
      tested = "#{math} td:last-child"

      assert has_element?(
               view,
               "#{tested} [data-participation=favorable]",
               "participation target"
             )

      refute has_element?(view, "#{tested}[class*=nd-cell]")

      # North Dakota material stays in the collapsed comparison section.
      refute has_element?(view, "#state-engagement table", "ND gr. 6–8")

      assert has_element?(
               view,
               ~s(#nd-comparison-toggle[aria-expanded="false"]),
               "North Dakota comparison"
             )

      assert has_element?(view, "#nd-comparison-body[hidden]")

      assert has_element?(view, "#nd-comparison #engagement-benchmark[data-status=compared]")

      # The documented rubric colors are kept (G1-M1 is 1 — Some Progress in Spr '26).
      assert has_element?(view, "#rating-G1-M1 .badge-soft.nd-text-warning", "1 · Some Progress")
    end

    test "Standard and Alternate views get no workbook verdicts", %{conn: conn, viewer: viewer} do
      {:ok, view, _html} = live(log_in(conn, viewer), "#{@dashboard}?state_type=Reg")

      assert has_element?(view, "#achievement-reading-all-grades", "40%–49%")
      refute has_element?(view, "#state-achievement [data-goal]")
      assert has_element?(view, "#achievement-type-note", "only in the Combined assessment view")
      # Growth has no assessment type and keeps its comparison.
      assert has_element?(view, "#growth-ela-all-grades [data-goal=G2-M3]")
    end

    test "the 36-month reference changes targets only; nothing is saved or rated",
         %{conn: conn, viewer: viewer, org: org} do
      counts = fn ->
        for r <- [
              Emisint.Improvement.ActualResult,
              Emisint.Improvement.ImplementationRating,
              Emisint.Improvement.PaymentEstimate
            ],
            do: r |> Ash.read!(tenant: org.id, authorize?: false) |> length()
      end

      before = counts.()
      {:ok, view, _html} = live(log_in(conn, viewer), "#{@dashboard}?period=review_18m")

      view |> form("#state-filters", goal_ref: "36m") |> render_change()

      assert_patch(
        view,
        "#{@dashboard}?goal_ref=36m&period=review_18m&state_subgroup=All&state_type=Comp&state_year=2024-2025"
      )

      # G2-M3 36-month target 51; 38 is still below.
      percentile = "#growth-ela-all-grades td:nth-child(9)"

      assert has_element?(
               view,
               percentile,
               "2024-2025 result · Growth percentile target: 51 · 36-month"
             )

      assert has_element?(view, "#goal-reference-note", "36-month target")

      # The PDF export carries the selection.
      assert has_element?(view, "a[href*='report.pdf'][href*='goal_ref=36m']")

      # Reference comparisons never touch review entries or payment.
      assert counts.() == before
      assert has_element?(view, "#payment-review_18m-estimate", "Awaiting review")
      assert has_element?(view, "#rating-G2-M3", "Not rated")
    end

    test "users without access to the school still cannot open it", %{conn: conn, org: org} do
      outsider = user!(org, :school_leader)

      assert {:error, {:live_redirect, %{to: "/school-goals"}}} =
               live(log_in(conn, outsider), @dashboard)
    end
  end

  describe "compared with North Dakota" do
    @with_state ~w(
      Insights-AssessmentPerformance-CSV-2024-2025-v20251113.csv
      Insights-AssessmentParticipation-CSV-2024-2025-v20251113.csv
      Insights-GrowthRate-CSV-2024-2025-v20251113.csv
      Insights-Engagement-Emotional-All-CSV-v20251202.csv
    )

    setup do
      import_insights!(Enum.map(@with_state, &Path.join([@fixtures, "with_state", &1])),
        institution_ids: ["4300429212", "99999"]
      )

      :ok
    end

    defp cell(row, n), do: "#{row} td:nth-child(#{n})"

    test "North Dakota comparisons stay in their own section; main statuses ignore them",
         %{conn: conn, viewer: viewer} do
      {:ok, view, _html} = live(log_in(conn, viewer), @dashboard)

      # Math 6 Novice 70%–79% is unfavorable against ND 25%, but the main
      # table compares it only with the school's schoolwide target.
      math6 = "#achievement-math-6"
      assert has_element?(view, "#{math6} td:nth-child(3)", "70%–79%")
      # The grade-level reference against the schoolwide 72% overlaps (amber).
      assert has_element?(view, "#{math6} td:nth-child(3).nd-cell-warning", "schoolwide target")
      refute has_element?(view, "#{math6} td:nth-child(3).nd-cell-error")
      refute has_element?(view, "#state-achievement table", "vs ND")
      refute has_element?(view, "#state-growth table", "vs ND")
      refute has_element?(view, "#state-engagement table", "ND gr. 6–8")

      # Growth percentile 64 (grade 8) is favorable against ND 50; no goal
      # applies to a grade, so no fill. All Grades 38 is red against the goal
      # (43) whatever North Dakota's value.
      # ELA 8 (64) is green against the schoolwide 43, from the school's
      # target only; the growth categories stay uncolored.
      assert has_element?(view, "#growth-ela-8 td:nth-child(9).nd-cell-success")
      refute has_element?(view, "#growth-ela-8 td:nth-child(5)[class*=nd-cell]")
      assert has_element?(view, "#growth-ela-all-grades td:nth-child(9).nd-cell-error")

      # The comparison section keeps its legend, coverage notes, Engagement
      # check and methodology.
      assert has_element?(
               view,
               "#nd-comparison #achievement-coverage",
               "Math: this school 6, 7, 8 · North Dakota 3, 4, 5, 6, 7, 8, 10"
             )

      assert has_element?(view, "#nd-comparison #growth-coverage", "All Grades rows are gray")
      assert has_element?(view, "#nd-comparison #nd-color-legend", "not school goal statuses")
      assert has_element?(view, "#nd-comparison #nd-legend-warning", "Cannot determine")
      refute has_element?(view, "#nd-legend-no-benchmark")

      assert has_element?(
               view,
               "#nd-comparison details#nd-methodology:not([open])",
               "docs/nd_insights_benchmarks.md"
             )

      assert has_element?(view, "#nd-comparison #engagement-benchmark > p", "grades 6–8")

      assert has_element?(
               view,
               "details#engagement-benchmark-details:not([open])",
               "Appendix C"
             )

      # Earlier years have no annual goal.
      assert has_element?(
               view,
               "#achievement-goal-years",
               "2024-2025 results have no annual goal"
             )

      assert has_element?(view, ~s(#nd-comparison-toggle[aria-expanded="false"]))
      assert has_element?(view, "#state-benchmark-key", "not a goal result or a test")

      novice = "#nd-row-achievement-math-6-novice"
      assert has_element?(view, "#{cell(novice, 5)}.nd-cell-error", "70%–79%")
      assert has_element?(view, cell(novice, 6), "25%")
      assert has_element?(view, "#{cell(novice, 7)} .nd-text-error", "Unfavorable vs ND")
      assert has_element?(view, cell(novice, 7), "whole published school range is above it")

      assert has_element?(
               view,
               "#nd-row-growth-ela-7-overall-growth-percentile .nd-text-error",
               "Unfavorable vs ND"
             )

      # Only rated measures appear: no intermediate levels.
      refute has_element?(view, "#nd-comparison-table", "Approaching")
      refute has_element?(view, "#nd-row-achievement-math-6-proficient")

      assert has_element?(
               view,
               "#nd-row-achievement-math-all-grades-novice",
               "Context only: grades differ (this school 6, 7, 8; ND 3, 4, 5, 6, 7, 8, 10)"
             )

      assert has_element?(view, "#nd-row-growth-math-8-meets-or-exceeds", "51%")

      assert has_element?(
               view,
               "#nd-row-engagement-emotional-none-committed",
               "Overlaps ND gr. 6–8"
             )

      assert has_element?(view, "#nd-comparison-pdf[href*=nd_comparison]")
    end

    test "another student group is never matched to the all-students benchmark",
         %{conn: conn, viewer: viewer} do
      {:ok, view, _html} = live(log_in(conn, viewer), "#{@dashboard}?state_subgroup=Female")

      assert has_element?(
               view,
               "#nd-row-achievement-math-all-grades-novice",
               "No North Dakota benchmark"
             )

      for tone <- ~w(success error warning) do
        # Engagement is all students regardless of the student-group filter.
        refute has_element?(
                 view,
                 "#nd-comparison-table tr:not([id^=nd-row-engagement]) .nd-text-#{tone}"
               )
      end
    end
  end

  describe "compared with North Dakota, exact published values" do
    # A copy of the official file in which one Fort Yates row (grade 6 Math,
    # Combined, all students) is rewritten with exact values, to exercise the
    # exact-value rules end to end. Fort Yates' real values are ranges.
    setup do
      name = "Insights-AssessmentPerformance-CSV-2024-2025-v20251113.csv"
      dir = Path.join(System.tmp_dir!(), "nd-exact-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)
      path = Path.join(dir, name)

      File.write!(
        path,
        [@fixtures, "with_state", name]
        |> Path.join()
        |> File.read!()
        |> String.replace(
          "4300429212,6,Math,Comp,All,All,0.7,0.79,0.3,0.39,0,0.2,0,0.2",
          "4300429212,6,Math,Comp,All,All,0.2,0.2,0.53,0.53,0.06,0.06,0.21,0.21"
        )
      )

      import_insights!([path], institution_ids: ["4300429212", "99999"])
      :ok
    end

    test "favorable, unfavorable and matches state compare exact published values",
         %{conn: conn, viewer: viewer} do
      {:ok, view, _html} = live(log_in(conn, viewer), @dashboard)

      # Novice 20% vs North Dakota 25%: lower is favorable.
      assert has_element?(view, "#nd-row-achievement-math-6-novice .nd-text-success", "Favorable")
      assert has_element?(view, "#nd-row-achievement-math-6-novice", "20%")
      # The main table is unaffected by the North Dakota comparison.
      assert has_element?(view, "#achievement-math-6 td:nth-child(3)", "20%")
      # Novice 20% is at or below the schoolwide 72% reference (also favorable
      # against ND, but the main table uses the school's target). Advanced
      # has no target.
      assert has_element?(
               view,
               "#achievement-math-6 td:nth-child(3).nd-cell-success",
               "At or below schoolwide target"
             )

      refute has_element?(view, "#achievement-math-6 td:nth-child(6)[class*=nd-cell]")

      # Advanced 21% vs 21%: matches the state, neutral (outlined, not colored).
      assert has_element?(view, "#nd-row-achievement-math-6-advanced", "Matches state")
      assert has_element?(view, "#nd-row-achievement-math-6-advanced td.nd-cell-neutral")

      # Proficient or Advanced 27% vs 48%: unfavorable.
      row = "#nd-row-achievement-math-6-proficient-or-advanced"
      assert has_element?(view, "#{row} .nd-text-error", "Unfavorable")
      assert has_element?(view, row, "27%")
      assert has_element?(view, "#achievement-math-6 td:nth-child(7)", "27%")
    end
  end
end
