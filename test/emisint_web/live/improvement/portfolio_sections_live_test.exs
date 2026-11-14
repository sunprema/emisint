defmodule EmisintWeb.Improvement.PortfolioSectionsLiveTest do
  @moduledoc """
  The `/school-goals` portfolio's collapsible detail sections: closed by
  default with the heading, summary figures and navigation visible; header
  buttons with aria-expanded and aria-controls; the open state kept in the
  URL across payment filter and view changes; Expand all / Collapse all.
  """
  use EmisintWeb.ConnCase, async: true

  import Emisint.ImprovementFixtures
  import Phoenix.LiveViewTest

  alias Emisint.Improvement.Seeds

  setup %{conn: conn} do
    org =
      seeded_organization!(
        name: "ND First sections",
        schools: Seeds.available_schools(),
        workbook_ratings?: true
      )

    %{conn: log_in(conn, user!(org, :emo_admin))}
  end

  defp expanded?(view, id),
    do:
      has_element?(view, ~s(##{id}-toggle[aria-expanded="true"])) and
        not has_element?(view, "##{id}-body[hidden]")

  defp collapsed?(view, id),
    do:
      has_element?(view, ~s(##{id}-toggle[aria-expanded="false"])) and
        has_element?(view, "##{id}-body[hidden]")

  test "closed by default; heading, summary figures and navigation stay visible", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/school-goals")

    for id <- ~w(portfolio-progress portfolio-payment-section) do
      assert collapsed?(view, id)
      assert has_element?(view, ~s(##{id}-toggle[aria-controls="#{id}-body"]))
      assert has_element?(view, ~s(##{id}-toggle[type="button"] .hero-chevron-right))
    end

    assert has_element?(view, "h1", "ND First")
    assert has_element?(view, "#portfolio-scope", "Showing 8 of 8 participants you can view")
    assert has_element?(view, "#glance-participants", "8 of 8")
    assert has_element?(view, "#glance-period", "Sum '26")
    # The summary figures are the AVERAGE row's (unchanged calculation).
    [systems] =
      Regex.run(~r/>\s*([0-9.]+)\s*</, view |> element("#average-sum_26-systems") |> render(),
        capture: :all_but_first
      )

    assert has_element?(view, "#glance-systems", systems)
    assert has_element?(view, "#glance-systems", "AVERAGE of 8 participants")

    # Navigation is outside the sections.
    assert has_element?(view, "#nd-tab-fort-yates-ms")
    assert has_element?(view, "#participant-drayton-public-school-district")

    refute has_element?(
             view,
             "#portfolio-progress-body #participant-drayton-public-school-district"
           )

    # Concise header summaries from existing data.
    assert has_element?(view, "#portfolio-progress-summary", "Seasonal ratings through Sum '26")

    assert has_element?(
             view,
             "#portfolio-payment-section-summary",
             "Current ratings preview, Sum '26, 18-month checkpoint: 8 estimated. Preview only."
           )

    assert has_element?(view, ~s(#sections-collapse-all[disabled]))
    refute has_element?(view, ~s(#sections-expand-all[disabled]))
  end

  test "a header toggles its section, and the state is in the URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/school-goals")

    view |> element("#portfolio-progress-toggle") |> render_click()
    assert_patch(view, "/school-goals?open=progress")
    assert expanded?(view, "portfolio-progress")
    assert collapsed?(view, "portfolio-payment-section")

    view |> element("#portfolio-progress-toggle") |> render_click()
    assert_patch(view, "/school-goals")
    assert collapsed?(view, "portfolio-progress")

    # A reload (or shared link) keeps it.
    {:ok, reloaded, _html} = live(conn, "/school-goals?open=payment")
    assert expanded?(reloaded, "portfolio-payment-section")
    assert collapsed?(reloaded, "portfolio-progress")

    # Unknown values are ignored.
    {:ok, odd, _html} = live(conn, "/school-goals?open=bogus,progress")
    assert expanded?(odd, "portfolio-progress")
  end

  test "payment controls are inside the payment section and keep it open", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/school-goals?open=progress,payment")

    assert has_element?(view, "#portfolio-payment-section-body #payment-view-tabs")
    assert has_element?(view, "#portfolio-payment-section-body #preview-form")

    view |> form("#preview-form", %{pay_period: "spr_26", pay_ref: "36m"}) |> render_change()

    assert_patch(
      view,
      "/school-goals?open=progress%2Cpayment&pay=preview&pay_period=spr_26&pay_ref=36m"
    )

    assert expanded?(view, "portfolio-progress")
    assert expanded?(view, "portfolio-payment-section")

    assert has_element?(
             view,
             "#portfolio-payment-section-summary",
             "Spr '26, 36-month checkpoint"
           )

    view |> element("#payment-view-formal") |> render_click()

    assert_patch(
      view,
      "/school-goals?open=progress%2Cpayment&pay=formal&pay_period=spr_26&pay_ref=36m"
    )

    assert expanded?(view, "portfolio-payment-section")

    assert has_element?(
             view,
             "#portfolio-payment",
             "Performance Based Payments (18-month review)"
           )

    assert has_element?(view, "#portfolio-payment-section-summary", "Formal review")
    # Moved into the disclosure, still present.
    assert has_element?(view, "#portfolio-payment-how", "No portfolio payment total is shown")
  end

  test "Expand all and Collapse all, keeping the payment filters", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/school-goals?pay_ref=36m")

    view |> element("#sections-expand-all") |> render_click()
    assert_patch(view, "/school-goals?open=progress%2Cpayment&pay_ref=36m")
    assert expanded?(view, "portfolio-progress")
    assert expanded?(view, "portfolio-payment-section")
    assert has_element?(view, ~s(#sections-expand-all[disabled]))

    view |> element("#sections-collapse-all") |> render_click()
    assert_patch(view, "/school-goals?pay_ref=36m")
    assert collapsed?(view, "portfolio-progress")
    assert collapsed?(view, "portfolio-payment-section")
  end

  test "essential labels stay beside their values", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/school-goals?open=payment")

    assert has_element?(
             view,
             "#preview-disclaimer",
             "Preview only. Final payment depends on formal review."
           )

    assert has_element?(view, "#preview-fort-yates-ms-provisional", "Provisional payment terms")

    assert has_element?(
             view,
             "#preview-dunseith-public-school-district-payment",
             "$48,611.11"
           )

    assert has_element?(view, "#portfolio-key", "missing, never zero")
  end
end
