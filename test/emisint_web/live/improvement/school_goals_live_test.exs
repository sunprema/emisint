defmodule EmisintWeb.Improvement.SchoolGoalsLiveTest do
  use EmisintWeb.ConnCase, async: true

  import Emisint.ImprovementFixtures
  import Phoenix.LiveViewTest

  require Ash.Query

  alias Emisint.Accounts.School
  alias Emisint.Improvement.{ActualResult, ImplementationRating}

  @dashboard "/school-goals/fort-yates-ms"

  setup do
    org = seeded_organization!(name: "Org A", workbook_ratings?: true)
    viewer = user!(org, :school_leader)
    membership!(viewer, school!(org), :viewer, org)

    %{org: org, contributor: contributor!(org), viewer: viewer}
  end

  defp current(resource, org, code, period_code) do
    metric = metric!(org, code)
    period = period!(org, period_code)

    resource
    |> Ash.Query.for_read(:current, %{}, tenant: org.id, authorize?: false)
    |> Ash.Query.filter(metric_id == ^metric.id and reporting_period_id == ^period.id)
    |> Ash.read!()
  end

  defp open_update(conn, user, code, period \\ "fal_26") do
    {:ok, view, _html} = live(log_in(conn, user), "#{@dashboard}?period=#{period}")
    view |> element("#update-#{code}") |> render_click()
    view
  end

  defp submit_actual(view, attrs) do
    view |> form("#actual-form", actual: attrs) |> render_submit()
  end

  describe "navigation and index" do
    test "the landing page is titled ND First with a factual introduction", %{
      conn: conn,
      contributor: user
    } do
      {:ok, view, _html} = live(log_in(conn, user), "/school-goals")

      assert has_element?(view, "h1", "ND First")
      assert has_element?(view, "#nd-first-intro a[href*=\"nd.gov/dpi\"]")
      assert has_element?(view, "nav a[href=\"/school-goals\"]", "ND First")
      refute has_element?(view, "#nd-import-link")
    end

    test "the ND Insights import button is on the Fort Yates dashboard, not the landing page",
         %{conn: conn, org: org, contributor: contributor} do
      admin = user!(org, :system_admin)
      admin_conn = log_in(conn, admin, %{"admin_org_id" => org.id})

      {:ok, landing, _html} = live(admin_conn, "/school-goals")
      refute has_element?(landing, "#nd-import-link")

      {:ok, dashboard, _html} = live(admin_conn, "/school-goals/fort-yates-ms")

      # Beside the official state results heading (shown even before any
      # import); Export PDF stays in the page header.
      assert has_element?(
               dashboard,
               ~s(#state-results #nd-import-link[href="/school-goals/fort-yates-ms/import"]),
               "Import ND Insights data"
             )

      assert has_element?(dashboard, "#state-results-empty")
      assert has_element?(dashboard, "#download-pdf", "Export PDF")
      refute has_element?(dashboard, "#state-results #download-pdf")

      # Other roles see the PDF export but no import button.
      {:ok, view, _html} = live(log_in(conn, contributor), "/school-goals/fort-yates-ms")
      assert has_element?(view, "#download-pdf")
      refute has_element?(view, "#nd-import-link")
    end

    test "the sidebar links to ND First and members see their school", %{
      conn: conn,
      contributor: user
    } do
      {:ok, view, html} = live(log_in(conn, user), "/school-goals")

      assert html =~ ~s(href="/school-goals")
      assert has_element?(view, "#school-fort-yates-ms", "Fort Yates Middle School")
    end

    test "users without a membership see no schools", %{conn: conn, org: org} do
      {:ok, view, _html} = live(log_in(conn, user!(org, :school_leader)), "/school-goals")

      assert has_element?(view, "#no-schools")
      refute has_element?(view, "#school-fort-yates-ms")
    end
  end

  describe "dashboard" do
    test "shows four goals, all 18 metrics, targets, annual goals and the payment card",
         %{conn: conn, viewer: user} do
      {:ok, view, html} = live(log_in(conn, user), "#{@dashboard}?period=fal_26")

      for n <- 1..4, do: assert(has_element?(view, "#goal-#{n}"))

      assert html |> LazyHTML.from_fragment() |> LazyHTML.query("tr[id^=metric-]") |> Enum.count() ==
               18

      # G4-M2 baseline 42.9%, 18-month 32.9%, 36-month 22.9%, lower is better
      assert has_element?(view, "#metric-G4-M2", "42.9%")
      assert has_element?(view, "#metric-G4-M2", "32.9%")
      assert has_element?(view, "#metric-G4-M2", "Lower is better")

      assert has_element?(view, "#annual-goals", "Proficient or Advanced")
      assert has_element?(view, "#annual-goals", "2030-2031")
      assert has_element?(view, "#annual-goals", "47%")

      # Goal 3's description is shown with the workbook typos corrected.
      assert has_element?(view, "#goal-3", "students performing at the novice level")
      assert has_element?(view, "#goal-3", "data-driven practices")
      refute html =~ "perfoming"
      refute html =~ "data-drive practices"

      assert has_element?(view, "#payment-card", "Awaiting review")
      assert has_element?(view, "#payment-calculation", "8 metrics")
      assert has_element?(view, "#payment-calculation", "10 metrics")
    end

    test "missing actuals show “Not reported”, never zero", %{conn: conn, viewer: user} do
      {:ok, view, _html} = live(log_in(conn, user), "#{@dashboard}?period=fal_26")

      assert has_element?(view, "#actual-G1-M1", "Not reported")
      refute has_element?(view, "#actual-G1-M1", "0%")
      assert has_element?(view, "#rating-G1-M1", "Not rated")
    end

    test "unconfirmed 36-month targets are flagged with their source cell", %{
      conn: conn,
      viewer: user
    } do
      {:ok, view, _html} = live(log_in(conn, user), @dashboard)

      # Muted text instead of a warning badge; the raw source stays out of the visible value.
      assert has_element?(view, "#metric-G1-M4 [data-target-value]", "Needs confirmation")
      refute has_element?(view, "#metric-G1-M4 .badge-warning", "Unconfirmed")
      refute has_element?(view, "#metric-G1-M4 [data-target-value]", "90")

      # Cell reference, raw value and explanation sit in collapsed source details.
      assert has_element?(
               view,
               "#target-36m-source-G1-M4-toggle[aria-expanded=false]",
               "Source details"
             )

      assert has_element?(view, "#target-36m-source-G1-M4.hidden", "Ft Yates Goals!P7: “90”")

      assert has_element?(
               view,
               "#target-36m-source-G1-M4.hidden",
               "The workbook lists 90; please confirm whether this means 90%."
             )

      assert has_element?(
               view,
               "#target-36m-source-G2-M4.hidden",
               "The workbook lists 80; please confirm whether this means 80%."
             )

      # Baseline and 18-month targets still show their values in the same rows.
      assert has_element?(view, "#metric-G1-M4 dl.items-baseline [data-target-value]", "30%")
      assert has_element?(view, "#metric-G1-M4 dl.items-baseline [data-target-value]", "70%")

      # Confirmed 36-month targets are unchanged.
      assert has_element?(view, "#metric-G1-M1 [data-target-value]", "95%")
      refute has_element?(view, "#target-36m-source-G1-M1")
    end

    test "the unconfirmed target keeps its flag and stays out of comparisons", %{org: org} do
      metric = metric!(org, "G1-M4")
      assert :target_36m_needs_confirmation in metric.flags
      assert metric.target_36m == nil
    end

    test "defaults to the latest period with entries and switches periods", %{
      conn: conn,
      viewer: user
    } do
      {:ok, view, _html} = live(log_in(conn, user), @dashboard)

      # Workbook ratings exist for Spr '26 and Sum '26.
      assert has_element?(view, "#period option[selected][value=sum_26]")

      view |> form("#period-select", period: "spr_26") |> render_change()
      assert_patch(view, "#{@dashboard}?period=spr_26")

      assert has_element?(view, "#rating-G1-M1", "Workbook import")
      # Soft badge with the accessible text color, like the rubric badges.
      assert has_element?(view, "#rating-G1-M1 .badge-soft.nd-text-info", "Workbook import")
      assert has_element?(view, "#rating-G1-M1", "Original author unknown")
      assert has_element?(view, "#rating-G1-M1", "Ft Yates Goals!E4")
      assert has_element?(view, "#rating-G1-M1", "workbook last updated Aug 18, 2026")
      # Seasonal Systems average from the workbook's Goals Dashboard.
      assert has_element?(view, "#seasonal-average-systems", "1.25")
      # Seasonal ratings never become a payment amount.
      assert has_element?(view, "#payment-card", "Awaiting review")
    end
  end

  describe "page polish" do
    test "Goal 4's review-column flag is one expandable note, not a badge per metric",
         %{conn: conn, org: org, viewer: user} do
      {:ok, view, _html} = live(log_in(conn, user), @dashboard)

      refute has_element?(view, "#goal-4 .badge", "Review column unconfirmed")

      assert has_element?(
               view,
               "#goal-4 #review-column-note-goal-4-toggle[aria-expanded=false]",
               "18-month review column needs confirmation"
             )

      note = "#review-column-note-goal-4.hidden"
      assert has_element?(view, note, "Ft Yates Goals!I26")
      assert has_element?(view, note, "Target Check")
      assert has_element?(view, note, "G4-M1, G4-M2, G4-M3, G4-M4")
      assert has_element?(view, note, "Performance-Based Payment!C4")

      for n <- 1..3, do: refute(has_element?(view, "#review-column-note-goal-#{n}"))

      # The underlying flags are unchanged.
      for code <- ~w(G4-M1 G4-M2 G4-M3 G4-M4) do
        assert :review_18m_column_heading_unconfirmed in metric!(org, code).flags
      end
    end

    test "in-page navigation links to Goals, Annual Targets and State Results", %{
      conn: conn,
      viewer: user
    } do
      {:ok, view, _html} = live(log_in(conn, user), @dashboard)

      for {href, label} <- [
            {"#goals", "Goals"},
            {"#annual-goals", "Annual Targets"},
            {"#state-results", "State Results"}
          ] do
        assert has_element?(view, ~s(#page-nav a[href="#{href}"]), label)
        assert has_element?(view, href)
      end

      assert has_element?(view, "#goals #goal-1")
    end
  end

  describe "compact layout" do
    test "import metadata is collapsed into source details on the dashboard but complete in history",
         %{conn: conn, viewer: user} do
      {:ok, view, _html} = live(log_in(conn, user), "#{@dashboard}?period=spr_26")

      assert has_element?(
               view,
               "#rating-source-G1-M1-toggle[aria-expanded=false]",
               "Workbook import"
             )

      assert has_element?(view, "#rating-source-G1-M1.hidden", "Original author unknown")
      assert has_element?(view, "#rating-source-G1-M1.hidden", "Ft Yates Goals!E4")

      {:ok, history, _html} = live(log_in(conn, user), "#{@dashboard}/metrics/G1-M1")
      assert has_element?(history, "#rating-history", "Original author unknown")
      assert has_element?(history, "#rating-history", "workbook last updated Aug 18, 2026")
      refute has_element?(history, "#rating-history .hidden")
    end

    test "each goal's planned steps expand without inventing step text", %{
      conn: conn,
      viewer: user
    } do
      {:ok, view, _html} = live(log_in(conn, user), "#{@dashboard}?period=fal_26")

      assert has_element?(
               view,
               "#steps-goal-1-toggle",
               "3 planned implementation steps in Fal '26"
             )

      assert has_element?(
               view,
               "#steps-goal-2-toggle",
               "4 planned implementation steps in Fal '26"
             )

      assert has_element?(view, "#steps-goal-1.hidden #steps-goal-1-no-doc", "TBD")
      assert has_element?(view, "#steps-goal-1", "Spr '26: 5")
      assert has_element?(view, "#steps-goal-1", "Sum '26: 4")

      {:ok, view, _html} = live(log_in(conn, user), "#{@dashboard}?period=win_27")

      assert has_element?(
               view,
               "#steps-goal-1-toggle",
               "No implementation steps recorded for Win '27"
             )
    end

    test "every metric row has its actions in the sticky column", %{conn: conn, contributor: user} do
      {:ok, view, html} = live(log_in(conn, user), "#{@dashboard}?period=fal_26")

      sticky =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("tr[id^=metric-] td.sticky")

      assert Enum.count(sticky) == 18
      assert has_element?(view, "#metric-G4-M4 td.sticky #update-G4-M4")
      assert has_element?(view, "#metric-G4-M4 td.sticky #history-G4-M4")
    end
  end

  describe "submitting actual results" do
    test "a seasonal result shows no target due and no status color", %{
      conn: conn,
      contributor: user
    } do
      view = open_update(conn, user, "G1-M1")
      submit_actual(view, %{value_state: "exact", value: "92", measurement_date: "2026-10-15"})

      assert has_element?(view, "#actual-G1-M1", "92%")
      assert has_element?(view, "#status-G1-M1", "No target due this period")
      refute has_element?(view, "#actual-G1-M1 [class*=nd-text-]")
      assert has_element?(view, "#status-legend", "Meets target")
    end

    test "percentages typed as 0–100 are stored as 0–1, with server-side author and time",
         %{conn: conn, org: org, contributor: user} do
      view = open_update(conn, user, "G2-M1")
      submit_actual(view, %{value_state: "exact", value: "24.5", measurement_date: "2026-10-15"})

      assert [entry] = current(ActualResult, org, "G2-M1", "fal_26")
      assert Decimal.equal?(entry.value, "0.245")
      assert entry.author_id == user.id
      assert entry.recorded_by_id == user.id
      assert entry.source == :manual
      assert %DateTime{} = entry.recorded_at

      assert has_element?(view, "#actual-G2-M1", "24.5%")
      assert has_element?(view, "#actual-G2-M1", to_string(user.email))
      # The rating is untouched.
      assert has_element?(view, "#rating-G2-M1", "Not rated")
    end

    test "out-of-range percentages are rejected without saving", %{
      conn: conn,
      org: org,
      contributor: user
    } do
      view = open_update(conn, user, "G2-M1")

      html =
        submit_actual(view, %{value_state: "exact", value: "245", measurement_date: "2026-10-15"})

      assert html =~ "must be between 0 and 100"
      assert current(ActualResult, org, "G2-M1", "fal_26") == []
    end

    test "ranges and suppressed values keep their shape", %{
      conn: conn,
      org: org,
      contributor: user
    } do
      view = open_update(conn, user, "G2-M1")
      view |> form("#actual-form", actual: %{value_state: "range"}) |> render_change()

      submit_actual(view, %{
        value_state: "range",
        range_low: "20",
        range_high: "29",
        measurement_date: "2026-10-15"
      })

      assert [range] = current(ActualResult, org, "G2-M1", "fal_26")
      assert Decimal.equal?(range.range_low, "0.2")
      assert Decimal.equal?(range.range_high, "0.29")
      assert range.value == nil
      assert has_element?(view, "#actual-G2-M1", "20%–29%")

      view |> element("#update-G3-M1") |> render_click()
      view |> form("#actual-form", actual: %{value_state: "suppressed"}) |> render_change()

      submit_actual(view, %{
        value_state: "suppressed",
        suppression_reason: "Fewer than 10 students tested"
      })

      assert [suppressed] = current(ActualResult, org, "G3-M1", "fal_26")
      assert suppressed.value_state == :suppressed
      assert has_element?(view, "#actual-G3-M1", "Suppressed")
      assert has_element?(view, "#actual-G3-M1", "Fewer than 10 students tested")
    end

    test "an explanation-only update needs notes and stores no value", %{
      conn: conn,
      org: org,
      contributor: user
    } do
      view = open_update(conn, user, "G2-M1")
      view |> form("#actual-form", actual: %{value_state: "unavailable"}) |> render_change()

      html = submit_actual(view, %{value_state: "unavailable"})
      assert html =~ "must explain why the result is unavailable"
      assert current(ActualResult, org, "G2-M1", "fal_26") == []

      submit_actual(view, %{value_state: "unavailable", notes: "State results not yet published"})
      assert [entry] = current(ActualResult, org, "G2-M1", "fal_26")
      assert entry.value == nil
      assert has_element?(view, "#actual-G2-M1", "Unavailable")
    end

    test "non-http evidence links are rejected", %{conn: conn, org: org, contributor: user} do
      view = open_update(conn, user, "G2-M1")

      submit_actual(view, %{
        value_state: "exact",
        value: "20",
        measurement_date: "2026-10-15",
        evidence: %{"0" => %{url: "javascript:alert(1)", label: "x"}}
      })

      assert current(ActualResult, org, "G2-M1", "fal_26") == []

      submit_actual(view, %{
        value_state: "exact",
        value: "20",
        measurement_date: "2026-10-15",
        evidence: %{"0" => %{url: "https://example.com/notes", label: "PD notes"}}
      })

      assert [%{evidence_links: [%{url: "https://example.com/notes"}]}] =
               current(ActualResult, org, "G2-M1", "fal_26")

      assert has_element?(
               view,
               ~s(#actual-G2-M1 a[href="https://example.com/notes"][rel="noopener noreferrer"])
             )
    end
  end

  describe "implementation ratings" do
    test "are submitted independently of actual results", %{
      conn: conn,
      org: org,
      contributor: user
    } do
      view = open_update(conn, user, "G2-M1")
      submit_actual(view, %{value_state: "exact", value: "30", measurement_date: "2026-10-15"})

      view
      |> form("#rating-form", rating: %{rating_state: "rated", score: "2"})
      |> render_submit()

      assert [%{score: 2, author_id: author}] =
               current(ImplementationRating, org, "G2-M1", "fal_26")

      assert author == user.id
      assert [%{value: value}] = current(ActualResult, org, "G2-M1", "fal_26")
      assert Decimal.equal?(value, "0.3")

      assert has_element?(view, "#rating-G2-M1", "Implementation on Track")
      assert has_element?(view, "#actual-G2-M1", "30%")
    end

    test "correcting a workbook import keeps the original and labels both", %{
      conn: conn,
      org: org,
      contributor: user
    } do
      [original] = current(ImplementationRating, org, "G1-M1", "spr_26")
      view = open_update(conn, user, "G1-M1", "spr_26")

      assert has_element?(view, "#rating-form", "Saving creates a correction")

      html =
        view
        |> form("#rating-form", rating: %{rating_state: "rated", score: "3"})
        |> render_submit()

      assert html =~ "is required"

      view
      |> form("#rating-form",
        rating: %{rating_state: "rated", score: "3", correction_reason: "Reviewed evidence"}
      )
      |> render_submit()

      assert [corrected] = current(ImplementationRating, org, "G1-M1", "spr_26")
      assert corrected.corrects_id == original.id
      assert corrected.author_id == user.id

      assert Ash.get!(ImplementationRating, original.id, tenant: org.id, authorize?: false).score ==
               original.score
    end
  end

  describe "corrections and history" do
    test "history shows the original as superseded, the correction as current, and its reason",
         %{conn: conn, org: org, contributor: user} do
      view = open_update(conn, user, "G2-M1")
      submit_actual(view, %{value_state: "exact", value: "24", measurement_date: "2026-10-15"})
      [original] = current(ActualResult, org, "G2-M1", "fal_26")

      html =
        submit_actual(view, %{value_state: "exact", value: "26", measurement_date: "2026-10-15"})

      assert html =~ "is required"

      submit_actual(view, %{
        value_state: "exact",
        value: "26",
        measurement_date: "2026-10-15",
        correction_reason: "Data entry error"
      })

      [correction] = current(ActualResult, org, "G2-M1", "fal_26")
      assert correction.corrects_id == original.id

      {:ok, history, _html} = live(log_in(conn, user), "#{@dashboard}/metrics/G2-M1")
      assert has_element?(history, "#entry-#{original.id}", "Superseded")
      assert has_element?(history, "#entry-#{original.id}", "24%")
      assert has_element?(history, "#entry-#{correction.id}", "Current")
      assert has_element?(history, "#entry-#{correction.id}", "Data entry error")
      assert has_element?(history, "#entry-#{correction.id}", "Correct this")
      refute has_element?(history, "#entry-#{original.id}", "Correct this")
    end

    test "“Correct this” opens the update panel for that metric and period", %{
      conn: conn,
      contributor: user
    } do
      {:ok, history, _html} = live(log_in(conn, user), "#{@dashboard}/metrics/G1-M1")

      {:ok, view, _html} =
        history
        |> element(~s(#rating-history a[href*="period=spr_26"]), "Correct this")
        |> render_click()
        |> follow_redirect(log_in(conn, user))

      assert has_element?(view, "#update-panel", "G1-M1")
      assert has_element?(view, "#rating-form", "Saving creates a correction")
    end

    test "a concurrent correction is rejected instead of overwritten", %{
      conn: conn,
      org: org,
      contributor: user
    } do
      [original] = current(ImplementationRating, org, "G1-M1", "spr_26")
      view = open_update(conn, user, "G1-M1", "spr_26")

      # Someone else corrects the same entry while the panel is open.
      Ash.create!(
        ImplementationRating,
        %{
          corrects_id: original.id,
          rating_state: :rated,
          score: 2,
          correction_reason: "Other reviewer"
        },
        action: :correct,
        tenant: org.id,
        actor: contributor!(org)
      )

      html =
        view
        |> form("#rating-form",
          rating: %{rating_state: "rated", score: "3", correction_reason: "Mine"}
        )
        |> render_submit()

      assert html =~ "already corrected by someone else"

      assert [%{correction_reason: "Other reviewer"}] =
               current(ImplementationRating, org, "G1-M1", "spr_26")
    end
  end

  describe "access boundaries" do
    test "viewers are read-only and forged events are refused", %{
      conn: conn,
      org: org,
      viewer: user
    } do
      {:ok, view, _html} = live(log_in(conn, user), "#{@dashboard}?period=fal_26")

      assert has_element?(view, "#read-only-badge")
      refute has_element?(view, "#update-G2-M1")

      metric = metric!(org, "G2-M1")
      assert render_hook(view, "open_update", %{"metric-id" => metric.id}) =~ "read-only access"
      refute has_element?(view, "#update-panel")

      assert render_hook(view, "save_actual", %{
               "actual" => %{
                 "value_state" => "exact",
                 "value" => "50",
                 "measurement_date" => "2026-10-15"
               }
             }) =~ "read-only access"

      assert render_hook(view, "save_rating", %{
               "rating" => %{"rating_state" => "rated", "score" => "3"}
             }) =~
               "read-only access"

      assert current(ActualResult, org, "G2-M1", "fal_26") == []
      assert current(ImplementationRating, org, "G2-M1", "fal_26") == []
    end

    test "viewers cannot open the editor through the URL", %{conn: conn, viewer: user} do
      {:ok, view, _html} = live(log_in(conn, user), "#{@dashboard}?period=spr_26&update=G1-M1")
      refute has_element?(view, "#update-panel")

      {:ok, history, _html} = live(log_in(conn, user), "#{@dashboard}/metrics/G1-M1")
      refute has_element?(history, "a", "Correct this")
    end

    test "users without a membership are redirected from direct URLs", %{conn: conn, org: org} do
      outsider = user!(org, :authorizer_liaison)

      for path <- [@dashboard, "#{@dashboard}/metrics/G1-M1"] do
        assert {:error, {:live_redirect, %{to: "/school-goals", flash: flash}}} =
                 live(log_in(conn, outsider), path)

        assert flash["error"] =~ "don't have access"
      end
    end

    test "a contributor of another school in the same org cannot open it", %{
      conn: conn,
      org: org,
      contributor: user
    } do
      Ash.create!(
        School,
        %{name: "Other School", slug: "other-school", state: "ND", state_entity_id: "0000000001"},
        tenant: org.id,
        authorize?: false
      )

      assert {:error, {:live_redirect, %{to: "/school-goals"}}} =
               live(log_in(conn, user), "/school-goals/other-school")
    end

    test "another organization's admin never sees this organization's entries", %{
      conn: conn,
      org: org,
      contributor: user
    } do
      view = open_update(conn, user, "G2-M1")
      submit_actual(view, %{value_state: "exact", value: "24", measurement_date: "2026-10-15"})

      org_b = seeded_organization!(name: "Org B")
      admin_b = user!(org_b, :emo_admin)

      # The same slug resolves inside Org B's own tenant.
      {:ok, b_view, _html} = live(log_in(conn, admin_b), "#{@dashboard}?period=fal_26")
      assert has_element?(b_view, "#actual-G2-M1", "Not reported")
      refute has_element?(b_view, "#actual-G2-M1", "24%")

      only_in_a =
        Ash.create!(
          School,
          %{name: "A Only", slug: "a-only", state: "ND", state_entity_id: "0000000002"},
          tenant: org.id,
          authorize?: false
        )

      assert {:error, {:live_redirect, %{to: "/school-goals"}}} =
               live(log_in(conn, admin_b), "/school-goals/#{only_in_a.slug}")
    end

    test "org admins can update any school in their organization", %{conn: conn, org: org} do
      admin = user!(org, :emo_admin)
      view = open_update(conn, admin, "G2-M1")
      submit_actual(view, %{value_state: "exact", value: "24", measurement_date: "2026-10-15"})

      assert [%{author_id: author}] = current(ActualResult, org, "G2-M1", "fal_26")
      assert author == admin.id
    end

    test "system admins see the organization selected in the org switcher", %{
      conn: conn,
      org: org,
      contributor: user
    } do
      view = open_update(conn, user, "G2-M1")
      submit_actual(view, %{value_state: "exact", value: "24", measurement_date: "2026-10-15"})

      system_admin = user!(nil, :system_admin)

      {:ok, view, _html} =
        live(
          log_in(conn, system_admin, %{"admin_org_id" => org.id}),
          "#{@dashboard}?period=fal_26"
        )

      assert has_element?(view, "#actual-G2-M1", "24%")
    end
  end

  describe "review checkpoints and growth percentiles (synthetic results)" do
    test "both reviews are selectable; a review shows the target due and formal rating entry", %{
      conn: conn,
      contributor: user
    } do
      {:ok, view, _html} = live(log_in(conn, user), "#{@dashboard}?period=review_18m")

      assert has_element?(view, "#period option[value=review_18m]", "18-Month Review")
      assert has_element?(view, "#period option[value=review_36m]", "36-Month Review")

      assert has_element?(
               view,
               "#status-G2-M3",
               "18-month target 43 · Not compared: no result reported"
             )

      refute has_element?(view, "#actual-G2-M3 [class*=nd-text-]")
      assert has_element?(view, "#rating-G2-M3", "Not rated")
      assert has_element?(view, "#payment-card", "Awaiting review")

      view |> element("#update-G2-M3") |> render_click()
      assert has_element?(view, "#review-entry-note")
      assert has_element?(view, "#actual-form")

      assert has_element?(
               view,
               "#rating-form #review-rating-heading",
               "Formal review rating (0–3)"
             )
    end

    test "growth percentiles display without a percent sign", %{conn: conn, contributor: user} do
      {:ok, view, html} = live(log_in(conn, user), "#{@dashboard}?period=fal_26")

      assert has_element?(view, "#unit-G2-M3", "Growth percentile")
      assert has_element?(view, "#unit-G3-M3", "Growth percentile")
      refute has_element?(view, "#unit-G2-M1")
      assert has_element?(view, "#metric-G2-M3", "Overall growth percentile (ELA)")

      row = html |> LazyHTML.from_fragment() |> LazyHTML.query("#metric-G2-M3") |> LazyHTML.text()
      assert row =~ "38"
      refute row =~ "38%"
      refute row =~ "43%"

      assert has_element?(
               view,
               "#insights-source-G2-M3",
               "Overall Growth Percentile · ELA · All Grades · All students"
             )

      refute has_element?(view, "#insights-source-G4-M2")
    end

    test "published percentiles are reference only until a year is chosen and saved", %{
      conn: conn,
      org: org,
      contributor: user
    } do
      # One uniquely keyed synthetic row (the published 2024-2025 value),
      # instead of a fixture import that would share keys with other async tests.
      file =
        Ash.Seed.seed!(Emisint.NdInsights.SourceFile, %{
          dataset: :growth_rate,
          file_name: "SYNTHETIC_growth_test.csv",
          sha256: "synthetic-#{System.unique_integer([:positive])}",
          publication_version: "test"
        })

      Ash.Seed.seed!(Emisint.NdInsights.StateResult, %{
        dataset: :growth_rate,
        academic_year: "2024-2025",
        institution_id: "4300429212",
        subject: "ELA",
        grade: "All Grades",
        subgroup: "All",
        measure: "OverallGrowthPercentile",
        unit: :percentile,
        value_state: :exact,
        value: Decimal.new("38"),
        natural_key: "synthetic|#{System.unique_integer([:positive])}",
        publication_version: "test",
        source_file_id: file.id
      })

      {:ok, view, _html} = live(log_in(conn, user), "#{@dashboard}?period=review_18m")

      assert has_element?(view, "#insights-latest-G2-M3", "Published 2024-2025: 38")
      assert has_element?(view, "#insights-latest-G2-M3", "reference only")
      # Not copied in as a result.
      assert has_element?(view, "#actual-G2-M3", "Not reported")

      view |> element("#update-G2-M3") |> render_click()
      assert has_element?(view, "#published-form")
      refute has_element?(view, "#published-none")
      # Every published year is offered; none is preselected and nothing is saved yet.
      assert has_element?(
               view,
               "#published_source_year option[value=\"2024-2025\"]",
               "2024-2025: 38"
             )

      assert has_element?(view, "#published_source_year option[value=\"\"][selected]")
      refute has_element?(view, "#published-preview")
      assert has_element?(view, "#published-form button[type=submit][disabled]")

      # Choosing a year shows exactly what will be saved, with its source year.
      view |> form("#published-form", published: %{source_year: "2024-2025"}) |> render_change()

      assert has_element?(
               view,
               "#published-preview",
               "Saving records 38 as the 18-Month Review result"
             )

      assert has_element?(view, "#published-preview", "Source year 2024-2025")
      refute has_element?(view, "#published-form button[type=submit][disabled]")
      assert current(ActualResult, org, "G2-M3", "review_18m") == []

      # Saving is the intentional step; the source year stays visible on the result.
      view |> form("#published-form", published: %{source_year: "2024-2025"}) |> render_submit()
      assert [entry] = current(ActualResult, org, "G2-M3", "review_18m")
      assert entry.source == :nd_insights
      assert has_element?(view, "#actual-G2-M3 .nd-text-error", "38")
      assert has_element?(view, "#actual-G2-M3", "ND Insights · source year 2024-2025")

      # Seasonal periods never offer the published value.
      view = open_update(conn, user, "G2-M3", "fal_26")
      refute has_element?(view, "#published-form")
    end

    for {value, class, label} <- [
          {"44", "nd-text-success", "Meets target"},
          {"43", "nd-text-success", "Meets target"},
          {"42", "nd-text-error", "Below target"}
        ] do
      test "a percentile of #{value} at the 18-month review: #{label}", %{
        conn: conn,
        org: org,
        contributor: user
      } do
        view = open_update(conn, user, "G2-M3", "review_18m")
        assert has_element?(view, "label", "Growth percentile (0–100, no % sign)")

        submit_actual(view, %{
          value_state: "exact",
          value: unquote(value),
          measurement_date: "2027-09-15"
        })

        assert [entry] = current(ActualResult, org, "G2-M3", "review_18m")
        assert Decimal.equal?(entry.value, unquote(value))

        assert has_element?(view, "#actual-G2-M3 .#{unquote(class)}", unquote(value))
        assert has_element?(view, "#status-G2-M3", "18-month target 43 · #{unquote(label)}")
        refute has_element?(view, "#actual-G2-M3", "#{unquote(value)}%")
      end
    end

    test "a lower-is-better metric at the 36-month review meets at or below its target", %{
      conn: conn,
      contributor: user
    } do
      view = open_update(conn, user, "G2-M2", "review_36m")
      submit_actual(view, %{value_state: "exact", value: "31", measurement_date: "2028-09-15"})

      assert has_element?(view, "#actual-G2-M2 .nd-text-success", "31%")
      assert has_element?(view, "#status-G2-M2", "36-month target 31% · Meets target")
    end

    test "history shows review entries as percentiles, and pre-decision entries as entered", %{
      conn: conn,
      org: org,
      contributor: user
    } do
      # Simulate a database from before the decision: the percent definition
      # and a result entered as a percentage, then the conversion.
      metric = metric!(org, "G3-M3")

      metric
      |> Ash.Changeset.for_update(
        :apply_unit_decision,
        %{
          unit: :percent,
          description: "Percentage of students met state growth expectations",
          performance_measure: :met_growth_expectation,
          baseline_value: Decimal.new("0.41"),
          target_18m: Decimal.new("0.46"),
          target_36m: Decimal.new("0.52"),
          source_values: Map.take(metric.source_values, ["baseline", "target_18m", "target_36m"])
        },
        tenant: org.id,
        authorize?: false
      )
      |> Ash.update!()

      view = open_update(conn, user, "G3-M3", "fal_26")
      submit_actual(view, %{value_state: "exact", value: "45", measurement_date: "2026-10-15"})
      assert [%{value: legacy}] = current(ActualResult, org, "G3-M3", "fal_26")
      assert Decimal.equal?(legacy, "0.45")

      admin = user!(nil, :system_admin)

      assert {:ok, %{restated: 1}} =
               Emisint.Improvement.GrowthPercentile.run(org.id, actor: admin)

      view = open_update(conn, user, "G3-M3", "review_18m")
      submit_actual(view, %{value_state: "exact", value: "47", measurement_date: "2027-09-15"})

      {:ok, history, _html} =
        live(log_in(conn, user), "/school-goals/fort-yates-ms/metrics/G3-M3")

      assert has_element?(history, "#history-unit", "Growth percentile")

      assert has_element?(
               history,
               "#history-original-wording",
               "Percentage of students met state growth expectations"
             )

      assert has_element?(history, "#actual-history", "18-Month Review")
      assert has_element?(history, "#actual-history", "47")
      assert has_element?(history, "#actual-history", "Unit correction")
      # The superseded entry keeps its original unit and is labeled.
      assert has_element?(history, "#actual-history", "45%")
      assert has_element?(history, "#actual-history", "Entered as %")

      [restated] = current(ActualResult, org, "G3-M3", "fal_26")
      assert Decimal.equal?(restated.value, "45")
      refute has_element?(history, "#entry-#{restated.id}", "45%")
    end

    test "viewers cannot enter review results", %{conn: conn, org: org, viewer: viewer} do
      {:ok, view, _html} = live(log_in(conn, viewer), "#{@dashboard}?period=review_18m")
      refute has_element?(view, "#update-G2-M3")

      render_hook(view, "save_actual", %{
        "actual" => %{
          "value_state" => "exact",
          "value" => "60",
          "measurement_date" => "2027-09-15"
        }
      })

      assert current(ActualResult, org, "G2-M3", "review_18m") == []
    end
  end

  describe "formal review ratings and the provisional payment estimate" do
    # Every Fort Yates metric except G2-M3 gets a formal 18-month review
    # rating of 3; the test enters G2-M3 through the form.
    defp review_ratings_except_g2_m3!(org, user) do
      period = period!(org, "review_18m")

      for metric <- Ash.read!(Emisint.Improvement.Metric, tenant: org.id, authorize?: false),
          metric.code != "G2-M3" do
        Ash.create!(
          ImplementationRating,
          %{metric_id: metric.id, reporting_period_id: period.id, rating_state: :rated, score: 3},
          action: :record_review,
          tenant: org.id,
          actor: user
        )
      end
    end

    test "entering the last review rating (an explicit 0) produces the estimate, a labeled subtotal",
         %{conn: conn, org: org, contributor: user} do
      review_ratings_except_g2_m3!(org, user)
      {:ok, view, _html} = live(log_in(conn, user), "#{@dashboard}?period=review_18m")

      assert has_element?(
               view,
               "#payment-review_18m-estimate",
               "Awaiting review: 1 review rating not recorded"
             )

      view |> element("#update-G2-M3") |> render_click()

      html =
        view
        |> form("#rating-form", rating: %{rating_state: "rated", score: "0"})
        |> render_submit()

      assert html =~ "Formal review rating saved."

      assert [%{score: 0, rating_state: :rated}] =
               current(ImplementationRating, org, "G2-M3", "review_18m")

      # Systems 3; Student Outcome (9 × 3 + 0) ÷ 10 = 2.7.
      # 3 × 0.70 + 2.7 × 0.30 = 2.91; 35,000 × 2.91 ÷ 3 = 33,950.00.
      assert has_element?(view, "#payment-calc-review_18m", "2.70")
      assert has_element?(view, "#payment-calc-review_18m", "2.91")
      assert has_element?(view, "#payment-review_18m-estimate", "$33,950.00")

      assert has_element?(
               view,
               "#payment-review_36m-estimate",
               "Awaiting review: 18 review ratings"
             )

      assert has_element?(
               view,
               "#payment-combined-text",
               "Subtotal $33,950.00 (18-month review only); the total awaits the other review"
             )

      assert has_element?(view, "#payment-card", "Estimated payment — provisional cap and split")

      assert has_element?(
               view,
               "#payment-terms-summary",
               "Working assumption, not confirmed contract terms"
             )

      # The details state the provisional sentence once, not the summary again.
      refute has_element?(view, "#payment-terms", "Working assumption")

      # The short summary keeps the provisional total, split and weights in
      # view; the provenance note and formula sit in the expandable details.
      assert has_element?(view, "#payment-terms-summary", "$70,000.00 total per school")
      assert has_element?(view, "#payment-terms-summary", "$35,000.00 to the 18-month review")
      refute has_element?(view, "#payment-terms-summary", "best-estimate")

      assert has_element?(
               view,
               "#payment-details #payment-terms",
               "Provisional estimate based on an assumed $70,000 total per school, split equally between the 18-month and 36-month checkpoints. Final payment terms are pending confirmation."
             )

      # No personal attribution or internal history anywhere on the page.
      html = render(view)

      for text <- ["Ram", "best-estimate", "our selected", "not terms he specified"] do
        refute html =~ text
      end

      assert has_element?(view, "#payment-details #payment-formula")
      assert has_element?(view, "#payment-review_18m", "70% / 30%")

      # Recording an estimate is for org admins only.
      refute has_element?(view, "#record-estimate-review_18m")
    end

    test "an org admin records an estimate, which keeps its assumptions", %{
      conn: conn,
      org: org,
      contributor: user
    } do
      review_ratings_except_g2_m3!(org, user)

      Ash.create!(
        ImplementationRating,
        %{
          metric_id: metric!(org, "G2-M3").id,
          reporting_period_id: period!(org, "review_18m").id,
          rating_state: :rated,
          score: 0
        },
        action: :record_review,
        tenant: org.id,
        actor: user
      )

      admin = user!(org, :emo_admin)
      {:ok, view, _html} = live(log_in(conn, admin), "#{@dashboard}?period=review_18m")

      assert has_element?(view, "#payment-estimates", "None recorded")
      html = view |> element("#record-estimate-review_18m") |> render_click()

      assert html =~ "Estimate recorded for the 18-Month Review: $33,950.00"
      assert has_element?(view, "#payment-estimates", "18-month review: $33,950.00")
      assert has_element?(view, "#payment-estimates", "cap $70,000.00, allocation $35,000.00")

      assert [estimate] =
               Ash.read!(Emisint.Improvement.PaymentEstimate, tenant: org.id, authorize?: false)

      assert Decimal.equal?(estimate.amount, "33950.00")
    end

    test "a forged record event from a contributor is refused", %{
      conn: conn,
      org: org,
      contributor: user
    } do
      {:ok, view, _html} = live(log_in(conn, user), "#{@dashboard}?period=review_18m")

      assert render_hook(view, "record_estimate", %{"checkpoint" => "review_18m"}) =~
               "Only org admins can record a payment estimate."

      assert Ash.count!(Emisint.Improvement.PaymentEstimate, tenant: org.id, authorize?: false) ==
               0
    end

    test "seasonal ratings never fill in the payment", %{conn: conn, org: org, contributor: user} do
      # The seeded workbook ratings are seasonal (spring and summer 2026).
      assert [%{rating_state: :rated}] = current(ImplementationRating, org, "G1-M1", "spr_26")
      {:ok, view, _html} = live(log_in(conn, user), "#{@dashboard}?period=spr_26")

      assert has_element?(
               view,
               "#payment-review_18m-estimate",
               "Awaiting review: 18 review ratings"
             )

      assert has_element?(view, "#payment-combined-text", "Awaiting review")
    end
  end
end
