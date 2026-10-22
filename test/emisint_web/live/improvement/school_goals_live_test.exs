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
    test "the sidebar links to School Goals and members see their school", %{
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

      assert has_element?(view, "#payment-card", "Awaiting review")
      assert has_element?(view, "#payment-card", "8 metrics")
      assert has_element?(view, "#payment-card", "10 metrics")
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
end
