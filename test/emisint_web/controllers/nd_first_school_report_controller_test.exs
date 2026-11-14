defmodule EmisintWeb.NdFirstSchoolReportControllerTest do
  # Never concurrent with other ND Insights imports (see Emisint.NdInsightsFixtures).
  use EmisintWeb.ConnCase, async: true, group: :nd_insights_import

  import Emisint.NdInsightsFixtures

  import Emisint.ImprovementFixtures

  alias Emisint.NdInsights.Importer
  alias Emisint.Reports.School.NdFirstSchoolPdf

  @fixtures Path.expand("../../fixtures/nd_insights", __DIR__)
  @report "/school-goals/fort-yates-ms/report.pdf"

  setup do
    org = seeded_organization!(name: "PDF Org", workbook_ratings?: true)
    viewer = user!(org, :school_leader)
    membership!(viewer, school!(org), :viewer, org)
    %{org: org, viewer: viewer}
  end

  describe "access" do
    test "signed-out users are sent to sign in", %{conn: conn} do
      assert redirected_to(get(conn, @report)) == "/sign-in"
    end

    test "users without access to the school are redirected", %{conn: conn, org: org} do
      outsider = user!(org, :school_leader)
      conn = conn |> log_in(outsider) |> get(@report)
      assert redirected_to(conn) == "/school-goals"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "don't have access"
    end

    test "members receive a PDF", %{conn: conn, viewer: viewer} do
      conn = conn |> log_in(viewer) |> get("#{@report}?period=spr_26")
      assert response_content_type(conn, :pdf) =~ "application/pdf"

      assert get_resp_header(conn, "content-disposition") == [
               ~s(inline; filename="nd_first_fort-yates-ms_spr_26.pdf")
             ]

      assert "%PDF" <> _ = conn.resp_body
    end

    test "system admins use the organization selected in the switcher", %{conn: conn, org: org} do
      admin = user!(nil, :system_admin)
      conn = conn |> log_in(admin, %{"admin_org_id" => org.id}) |> get(@report)
      assert "%PDF" <> _ = conn.resp_body
    end
  end

  describe "report data" do
    defp scope(user), do: %Emisint.Scope{current_user: user, current_tenant: user.organization_id}

    test "identifies the period, filters, generation and sources", %{viewer: viewer} do
      import_insights!(
        [
          Path.join(@fixtures, "Insights-AssessmentPerformance-CSV-2024-2025-v20251113.csv"),
          Path.join(@fixtures, "Insights-AssessmentPerformance-CSV-2023-2024-v20240824.csv")
        ],
        institution_ids: ["4300429212"]
      )

      {:ok, data, _} =
        NdFirstSchoolPdf.build(scope(viewer), "fort-yates-ms", %{
          "period" => "spr_26",
          "state_type" => "Alt",
          "state_subgroup" => "All"
        })

      assert data.report.period == "Spr '26"

      # Goal 3's description is corrected for display only.
      goal3 = Enum.find(data.goals, &(&1.title == "Goal 3: Mathematics Growth"))
      assert goal3.description =~ "students performing at the novice level"
      assert goal3.description =~ "data-driven practices"
      refute inspect(data) =~ "perfoming"
      refute inspect(data) =~ "data-drive practices"
      assert data.report.state_year == "2024-2025"
      assert data.report.state_type == "Alternate"
      assert data.report.generated_at =~ "UTC"
      assert data.report.generated_by == to_string(viewer.email)

      assert Enum.any?(
               data.sources,
               &(&1 =~ "Insights-AssessmentPerformance-CSV-2024-2025-v20251113.csv")
             )

      # The inventory lists only the imported files the report doesn't use, so
      # no file is printed twice; the note gives both counts.
      assert [other] = data.file_inventory
      assert other =~ ~r/^AssessmentPerformance: 2023-2024 v20240824 [0-9a-f]{12}…$/
      refute Enum.any?(data.sources, &(&1 =~ "2023-2024"))

      assert data.file_inventory_note =~
               "2 ND Insights files are imported for this school: the 1 under “Sources used in this report”, and the 1 below"

      refute Enum.any?(data.sources, &(&1 =~ "6311")), "% tested isn't compared for Alternate"

      # Alternate has no published Fort Yates rows: an explicit empty state, not zeros.
      assert data.state.achievement == []

      assert data.state.achievement_empty =~
               "No published achievement results for Alternate assessment"
    end

    test "keeps missing, unconfirmed and pending labels from the dashboard rules", %{
      viewer: viewer
    } do
      import_insights!(
        [Path.join(@fixtures, "Insights-AssessmentPerformance-CSV-2024-2025-v20251113.csv")],
        institution_ids: ["4300429212"]
      )

      {:ok, data, _} =
        NdFirstSchoolPdf.build(scope(viewer), "fort-yates-ms", %{"period" => "fal_26"})

      g1 = hd(data.goals)
      m4 = Enum.find(g1.metrics, &(&1.code == "G1-M4"))
      assert m4.actual == "Not reported"
      assert m4.rating == "Not rated"
      assert m4.target_36m == "Needs confirmation (Ft Yates Goals!P7 lists 90)"

      [row | _] = data.annual
      assert row.ela_published == "No matching results in the imported data"

      [reading | _] = data.state.achievement
      assert reading.subject == "ELA (Reading)"
      # Main tables show school goals. 2024-25 has no annual goal (none is
      # substituted), so the derived value is plain; the workbook Proficient
      # target is gray (assessment type unconfirmed), never "Intermediate".
      assert reading.derived == %{
               text: "20%–39%",
               tone: "none",
               fill: "false",
               label: "",
               caveat: "",
               line: ""
             }

      # 20%–29% vs the 18-month target 27%: the range overlaps (amber).
      assert reading.proficient == %{
               text: "20%–29%",
               tone: "warning",
               fill: "true",
               label: "Range overlaps target",
               caveat: "",
               line: "2024-2025 result vs 18-month target 27% · G2-M1 ELA Proficient"
             }

      # Novice 40%–49% vs 39% (lower is better): above the target (red).
      assert %{tone: "error", label: "Above target"} = reading.novice

      assert data.state.notes.achievement == [
               "Reference comparison; Combined assessment assumed for workbook targets.",
               "2024-2025 results predate the plan, so they are compared against future targets.",
               "Grade-level colors compare each grade’s results with the schoolwide target for reference. These are not separate grade-level goals."
             ]

      # Grade rows: the schoolwide target as a reference, never a grade goal.
      ela8 =
        Enum.find(data.state.achievement, &(&1.subject == "ELA (Reading)" and &1.grade == "8"))

      assert ela8.proficient == %{
               text: "40%–49%",
               tone: "success",
               fill: "true",
               label: "At or above schoolwide target",
               caveat: "",
               line: "Schoolwide reference: 27% · 18-month"
             }

      assert %{tone: "error", label: "Above schoolwide target"} = ela8.novice
      # No targets for Approaching Proficiency, Advanced or Science.
      assert ela8.partially.tone == "none" and ela8.advanced.tone == "none"

      assert data.state.legend.intro =~ "not an official ND FIRST scoring method"
      assert data.state.legend.reference =~ "18-month target as a reference"
      assert data.report.goal_reference == "18-month target"

      assert data.state.goal_years_note =~
               "start in 2025-2026, so 2024-2025 results have no annual goal"

      # Goal colors only where a confirmed rule exists: rubric tones for
      # ratings and goal status for exact comparisons.
      assert row.ela_tone == "neutral"
      assert m4.rating_tone == "neutral"
      assert Enum.map(data.rubric, & &1.tone) == ~w(success info warning error)
      assert data.payment.label == "Estimated payment — provisional terms"

      assert data.payment.combined ==
               "Awaiting review; the 36-month review payment allocation needs confirmation"

      assert data.payment.terms_summary =~ "Working assumption, not confirmed contract terms"
      assert data.payment.terms_summary =~ "18-month review: up to $70,000.00"

      assert data.payment.terms_summary =~
               "36-month review: payment allocation needs confirmation"

      # The appendix states the provisional sentence once.
      assert data.payment.terms ==
               "Provisional estimate, not confirmed contract terms. The 18-month amount follows the workbook's “Performance-Based Payment” sheet (rows 4–11, column I: weighted score ÷ 3 × $70,000). No source sets a 36-month payment allocation, so the 36-month review shows its weighted score and its payment allocation needs confirmation."

      for text <- ["Ram", "best-estimate", "our selected", "not terms he specified"] do
        refute inspect(data) =~ text
      end

      assert data.payment.terms_summary =~ "18-month review: up to $70,000.00"
      refute data.payment.terms_summary =~ "best-estimate"
      assert data.payment.formula =~ "checkpoint allocation × weighted review score ÷ 3"
      refute Map.has_key?(data.payment, :cap_note)

      # Annual Targets rows use the shared bound rule (ResultGoals.annual/2).
      assert NdFirstSchoolPdf.annual_text(%{
               status: :overlaps,
               direction: :higher_is_better,
               value: "20%–39%"
             }) == "20%–39% derived · Range overlaps target"
    end

    test "focuses on goals by default; the North Dakota comparison is optional", %{
      viewer: viewer
    } do
      # Assert the import itself succeeded, so a failure shows its reason.
      {:ok, [%{created: created}]} =
        Importer.import_files(
          [
            Path.join([
              @fixtures,
              "with_state",
              "Insights-AssessmentPerformance-CSV-2024-2025-v20251113.csv"
            ])
          ],
          institution_ids: ["4300429212", "99999"]
        )

      assert created > 0

      {:ok, data, _} = NdFirstSchoolPdf.build(scope(viewer), "fort-yates-ms", %{})
      refute data.nd_comparison.included
      # The main tables show school goals only, whatever North Dakota's values:
      # grade 6 has no schoolwide goal, so Novice 70%–79% (red against ND 25%
      # in the comparison) is plain here.
      math6 = Enum.find(data.state.achievement, &(&1.subject == "Math" and &1.grade == "6"))
      plain = &%{text: &1, tone: "none", fill: "false", label: "", caveat: "", line: ""}
      # Grade 6 Novice 70%–79% (red against ND 25% in the comparison)
      # overlaps the schoolwide 72% reference: amber, whatever ND's value.
      assert %{
               tone: "warning",
               label: "Range overlaps schoolwide target",
               line: "Schoolwide reference: 72% · 18-month"
             } = math6.novice

      assert math6.advanced == plain.("0%–20%")
      assert math6.partially == plain.("30%–39%")
      # % tested: the participation target is a label only, never a filled cell.
      assert math6.tested.fill == "false"

      math_all =
        Enum.find(data.state.achievement, &(&1.subject == "Math" and &1.grade == "All Grades"))

      # ND calls this "Context only"; the goal view compares 70%–79% with
      # the workbook's 72% (lower is better): the range overlaps.
      assert %{
               tone: "warning",
               label: "Range overlaps target",
               line:
                 "2024-2025 result vs 18-month target 72% · G3-M2 Math Novice, lower is better"
             } = math_all.novice

      cells =
        for row <- data.state.achievement ++ data.state.growth ++ data.state.engagement,
            %{label: label} <- Map.values(row),
            do: label

      refute Enum.any?(cells, &(&1 =~ ~r/ND|Favorable|Unfavorable|Intermediate|Context only/))

      assert Enum.map(data.state.legend.items, & &1.tone) == ~w(success error warning muted)
      refute Map.has_key?(data.state, :achievement_coverage)
      assert Enum.any?(data.appendix, &(&1 =~ "School goals. Matching."))
      refute Enum.any?(data.appendix, &(&1 =~ "to a range of values"))
      refute Enum.any?(data.sources, &(&1 =~ "nd_insights_benchmarks.md"))
      refute Enum.any?(data.appendix ++ data.guidance, &(&1 =~ "percentage point is allowed"))

      {:ok, data, _} =
        NdFirstSchoolPdf.build(scope(viewer), "fort-yates-ms", %{"nd_comparison" => "1"})

      # The optional comparison keeps the North Dakota legend, notes and methodology.
      assert Enum.map(data.nd_comparison.legend.items, & &1.tone) ==
               ~w(success error warning neutral muted)

      assert data.nd_comparison.coverage == [
               "Achievement: ELA (Reading) All Grades is context only: this school's All Grades covers grades 6, 7, 8; North Dakota's covers 3, 4, 5, 6, 7, 8, 10.",
               "Achievement: Math All Grades is context only: this school's All Grades covers grades 6, 7, 8; North Dakota's covers 3, 4, 5, 6, 7, 8, 10.",
               "Achievement: Science All Grades is context only: this school's All Grades covers grades 8; North Dakota's covers 4, 8, 10."
             ]

      assert Enum.any?(data.appendix, &(&1 =~ "to a range of values"))
      assert Enum.any?(data.appendix, &(&1 =~ "never midpoints"))
      # The main tables are the same with or without the comparison.
      assert Enum.find(data.state.achievement, &(&1.subject == "Math" and &1.grade == "6")) ==
               math6

      assert data.nd_comparison.included
      assert data.nd_comparison.note =~ "not a goal result"

      novice =
        Enum.find(
          data.nd_comparison.rows,
          &(&1.subject == "Math" and &1.grade == "6" and &1.measure == "Novice")
        )

      # The whole published range is above the state value: unfavorable.
      assert %{
               school: "70%–79%",
               state: "25%",
               label: "Unfavorable vs ND",
               tone: "error"
             } = novice

      assert novice.explanation =~ "Lower Novice is favorable"

      refute Enum.any?(data.nd_comparison.rows, &(&1.measure == "Proficient"))

      all =
        Enum.find(
          data.nd_comparison.rows,
          &(&1.subject == "Math" and &1.grade == "All Grades" and &1.measure == "Novice")
        )

      assert all.label =~ "Context only: grades differ"
      assert novice.state == "25%"
      refute novice.explanation =~ "A comparison of published values"
    end

    test "the selected reference checkpoint, colors and caveats reach the PDF", %{viewer: viewer} do
      import_insights!(
        [Path.join(@fixtures, "Insights-GrowthRate-CSV-2024-2025-v20251113.csv")],
        institution_ids: ["4300429212"]
      )

      for {param, label, target} <- [
            {"18m", "18-month target", "43"},
            {"36m", "36-month target", "51"}
          ] do
        {:ok, data, _} =
          NdFirstSchoolPdf.build(scope(viewer), "fort-yates-ms", %{"goal_ref" => param})

        assert data.report.goal_reference == label
        ela = Enum.find(data.state.growth, &(&1.subject == "ELA" and &1.grade == "All Grades"))

        # 38 is below either target: red, a reference comparison, no % sign.
        assert %{
                 text: "38",
                 tone: "error",
                 fill: "true",
                 label: "Below target",
                 caveat: ""
               } = ela.percentile

        assert data.state.notes.growth == [
                 "Reference comparison against workbook targets.",
                 "2024-2025 results predate the plan, so they are compared against future targets.",
                 "Grade-level colors compare each grade’s growth percentile with the schoolwide target for reference. These are not separate grade-level goals."
               ]

        # Grade rows: ELA 7 is 35, ELA 8 is 64 (both checkpoints: 43 and 51).
        ela7 = Enum.find(data.state.growth, &(&1.subject == "ELA" and &1.grade == "7"))
        ela8 = Enum.find(data.state.growth, &(&1.subject == "ELA" and &1.grade == "8"))

        assert %{text: "35", tone: "error", label: "Below schoolwide target"} = ela7.percentile

        assert %{text: "64", tone: "success", label: "At or above schoolwide target"} =
                 ela8.percentile

        assert ela7.percentile.line ==
                 "Growth percentile target: #{target} · #{String.replace(label, " target", "")} · Schoolwide reference"

        # No percentile target on the growth categories.
        assert ela7.meets.tone == "none" and ela7.does_not_meet.tone == "none"

        assert ela.percentile.line ==
                 "2024-2025 result · Growth percentile target: #{target} · #{String.replace(label, " target", "")} · G2-M3"
      end
    end

    test "without North Dakota rows the optional comparison says so", %{viewer: viewer} do
      # Assert the import itself succeeded, so a failure shows its reason.
      {:ok, [%{created: created}]} =
        Importer.import_files(
          [Path.join(@fixtures, "Insights-AssessmentPerformance-CSV-2024-2025-v20251113.csv")],
          institution_ids: ["4300429212"]
        )

      assert created > 0

      {:ok, data, _} =
        NdFirstSchoolPdf.build(scope(viewer), "fort-yates-ms", %{"nd_comparison" => "1"})

      assert data.nd_comparison.note =~ "No North Dakota benchmark rows"
      assert data.nd_comparison.rows == []
    end

    test "metric rows carry the goal status; nothing reported means no status", %{
      viewer: viewer
    } do
      {:ok, data, _} = NdFirstSchoolPdf.build(scope(viewer), "fort-yates-ms", %{})
      m1 = hd(hd(data.goals).metrics)
      assert m1.actual == "Not reported"
      assert m1.status == ""
      assert m1.status_tone == "neutral"

      # Ratings: score and full label together, with the rubric tone.
      {:ok, data, _} =
        NdFirstSchoolPdf.build(scope(viewer), "fort-yates-ms", %{"period" => "sum_26"})

      g1m1 = hd(hd(data.goals).metrics)
      assert g1m1.rating == "2 · Implementation on Track"
      assert g1m1.rating_tone == "info"
      assert Enum.any?(data.guidance, &(&1 =~ "Seasonal periods have no target due"))

      # Missing actual results, missing ratings and published-but-unrated
      # measures are told apart.
      assert Enum.any?(
               data.guidance,
               &(&1 =~ "“Not reported” means no actual result has been submitted")
             )

      assert Enum.any?(data.guidance, &(&1 =~ "“Not rated” means no implementation rating"))

      assert Enum.any?(
               data.guidance,
               &(&1 =~ "“Reference comparison — review year unconfirmed”")
             )

      # Workbook provenance is a compact reference, explained once in the appendix.
      assert g1m1.rating_source =~ ~r/^\[W\] Ft Yates Goals!/
      refute g1m1.rating_source =~ "original author unknown"
      assert Enum.any?(data.appendix, &(&1 =~ "does not record who entered each value"))
      assert Enum.any?(data.appendix, &(&1 =~ "P7 and P16"))
    end

    test "a school the user cannot read is not found", %{org: org} do
      outsider = user!(org, :school_leader)
      assert {:error, :not_found} = NdFirstSchoolPdf.build(scope(outsider), "fort-yates-ms")
    end
  end

  describe "review checkpoints and growth percentiles (synthetic results)" do
    test "the PDF matches the dashboard: percentile, target due, status and no review rating",
         %{conn: conn, org: org, viewer: viewer} do
      contributor = contributor!(org)

      for {code, value} <- [{"G2-M3", "42"}, {"G3-M3", "46"}] do
        Ash.create!(
          Emisint.Improvement.ActualResult,
          %{
            metric_id: metric!(org, code).id,
            reporting_period_id: period!(org, "review_18m").id,
            value_state: :exact,
            value: Decimal.new(value),
            measurement_date: ~D[2027-09-15]
          },
          action: :record,
          tenant: org.id,
          actor: contributor
        )
      end

      {:ok, data, filename} =
        NdFirstSchoolPdf.build(
          %Emisint.Scope{current_user: viewer, current_tenant: org.id},
          "fort-yates-ms",
          %{"period" => "review_18m"}
        )

      assert filename == "nd_first_fort-yates-ms_review_18m.pdf"
      assert data.report.period == "18-Month Review"
      assert data.report.period_scope == "review actuals and formal review ratings"
      rows = data.goals |> Enum.flat_map(& &1.metrics) |> Map.new(&{&1.code, &1})

      assert %{
               unit: "Growth percentile",
               description: "Overall growth percentile (ELA)",
               baseline: "38",
               target_18m: "43",
               target_36m: "51",
               actual: "42",
               status: "18-month target 43 · Below target",
               status_tone: "error",
               rating: "Not rated",
               rating_tone: "neutral"
             } = rows["G2-M3"]

      assert %{actual: "46", status: "18-month target 46 · Meets target", status_tone: "success"} =
               rows["G3-M3"]

      assert rows["G2-M3"].source_note =~
               "Overall Growth Percentile · ELA · All Grades · All students"

      assert %{unit: "", source_note: "", baseline: "22%"} = rows["G2-M1"]
      assert %{status: "18-month target 39% · Not compared: no result reported"} = rows["G2-M2"]

      assert data.payment.combined ==
               "Awaiting review; the 36-month review payment allocation needs confirmation"

      assert Enum.map(data.averages, & &1.average) == [
               "0 of 8 applicable metrics rated",
               "0 of 10 applicable metrics rated"
             ]

      assert Enum.map(data.payment.checkpoints, & &1.estimate) == [
               "Awaiting review: 18 review ratings not recorded (0 of 18 applicable metrics rated)",
               "Awaiting review: 18 review ratings not recorded; payment allocation needs confirmation (0 of 18 applicable metrics rated)"
             ]

      conn = conn |> log_in(viewer) |> get("#{@report}?period=review_18m")
      assert "%PDF" <> _ = conn.resp_body
    end
  end

  describe "estimated payment" do
    test "a complete checkpoint shows the same estimate wording as the dashboard, and renders", %{
      conn: conn,
      org: org,
      viewer: viewer
    } do
      contributor = contributor!(org)
      admin = user!(org, :emo_admin)
      period = period!(org, "review_18m")

      for metric <- Ash.read!(Emisint.Improvement.Metric, tenant: org.id, authorize?: false) do
        Ash.create!(
          Emisint.Improvement.ImplementationRating,
          %{
            metric_id: metric.id,
            reporting_period_id: period.id,
            rating_state: :rated,
            score: if(metric.category == :systems, do: 3, else: 1)
          },
          action: :record_review,
          tenant: org.id,
          actor: contributor
        )
      end

      Ash.create!(Emisint.Improvement.PaymentEstimate, %{reporting_period_id: period.id},
        action: :record,
        tenant: org.id,
        actor: admin
      )

      {:ok, data, _filename} =
        NdFirstSchoolPdf.build(
          %Emisint.Scope{current_user: viewer, current_tenant: org.id},
          "fort-yates-ms",
          %{"period" => "review_18m"}
        )

      # 3 × 0.70 + 1 × 0.30 = 2.4; 70,000 × 2.4 ÷ 3 = 56,000 (the workbook's I column).
      assert [eighteen, thirty_six] = data.payment.checkpoints

      assert eighteen == %{
               label: "18-month review",
               systems_average: "3.00",
               outcomes_average: "1.00",
               weights: "70% / 30%",
               weighted: "2.40",
               allocation: "$70,000.00",
               estimate: "$56,000.00 (18 of 18 applicable metrics rated)"
             }

      assert thirty_six.allocation == "Needs confirmation"

      assert thirty_six.estimate ==
               "Awaiting review: 18 review ratings not recorded; payment allocation needs confirmation (0 of 18 applicable metrics rated)"

      assert data.payment.combined ==
               "Subtotal $56,000.00 (18-month review only); the 36-month review payment allocation needs confirmation"

      assert [recorded] = data.payment.estimates

      assert recorded =~
               "18-month review: $56,000.00 · Estimated payment — provisional terms"

      assert Enum.map(data.averages, & &1.average) == [
               "8 of 8 applicable metrics rated",
               "10 of 10 applicable metrics rated"
             ]

      conn = conn |> log_in(viewer) |> get("#{@report}?period=review_18m")
      assert "%PDF" <> _ = conn.resp_body
    end
  end
end
