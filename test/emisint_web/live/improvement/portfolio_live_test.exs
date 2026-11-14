defmodule EmisintWeb.Improvement.PortfolioLiveTest do
  @moduledoc """
  The ND FIRST portfolio summary on `/school-goals`: the workbook's "Goals
  Dashboard" and "Performance-Based Payment" sheets, one linked row per
  participant, missing values shown as missing, filtered by permissions, with
  the school navigation kept.
  """
  use EmisintWeb.ConnCase, async: true

  import Emisint.ImprovementFixtures
  import Phoenix.LiveViewTest

  alias Emisint.Improvement.Seeds

  setup do
    org =
      seeded_organization!(
        name: "ND First portfolio page",
        schools: Seeds.available_schools(),
        workbook_ratings?: true
      )

    %{org: org, admin: user!(org, :emo_admin)}
  end

  test "an org admin sees every participant, linked, with the workbook's sheets", %{
    conn: conn,
    admin: admin
  } do
    {:ok, view, html} = live(log_in(conn, admin), "/school-goals")

    assert has_element?(
             view,
             "#portfolio-progress",
             "Overall Goal Progress — Average Rubric Score"
           )

    # The current-ratings preview is the default payment view; the formal
    # review table is its own view (checked below).
    assert has_element?(view, "#portfolio-preview", "Estimated payment based on current ratings.")
    refute has_element?(view, "#portfolio-payment")

    for slug <-
          ~w(fort-yates-ms oberon-elementary valley-middle-school drayton-public-school-district dunseith-public-school-district mandaree-public-school-district warwick-public-school-district) do
      assert has_element?(view, ~s(#portfolio-link-#{slug}[href="/school-goals/#{slug}"]))
    end

    # Buildings are never portfolio rows.
    refute html =~ ~s(id="portfolio-row-drayton-elementary")
    refute html =~ ~s(id="portfolio-row-warwick-high-school")

    # Workbook values (Goals Dashboard!E5:H5, Fort Yates).
    assert has_element?(view, "#fort-yates-ms-spr_26-systems", "1.25")
    assert has_element?(view, "#fort-yates-ms-spr_26-outcomes", "1.6")
    assert has_element?(view, "#fort-yates-ms-sum_26-systems", "1.38")
    # Valley, Spr '26: the workbook marks 3 Systems metrics N/A (Valley Goals!E6,
    # E13, E41). They are excluded, not missing: 13 of 13 applicable, "3 N/A".
    assert has_element?(view, "#portfolio-row-valley-middle-school", "3 N/A")
    refute has_element?(view, "#portfolio-row-valley-middle-school", "13/16")

    # Missing values are "—", never 0.
    assert has_element?(view, "#fort-yates-ms-fal_26-systems[data-missing]", "—")
    assert has_element?(view, "#fort-yates-ms-check_18m-systems[data-missing]", "—")
    assert has_element?(view, "#portfolio-average", "of 8 participants shown")

    # Formal review payment: explicit statuses, no invented total.
    {:ok, formal, _html} = live(log_in(conn, admin), "/school-goals?pay=formal")
    refute has_element?(formal, "#portfolio-preview")

    assert has_element?(
             formal,
             "#portfolio-payment",
             "Performance Based Payments (18-month review)"
           )

    assert has_element?(formal, "#fort-yates-ms-estimate", "Awaiting review")

    assert has_element?(
             formal,
             "#oberon-elementary-estimate",
             "Awaiting review: 21 review ratings"
           )

    assert has_element?(formal, "#portfolio-payment", "No portfolio payment total is shown")

    # The workbook's Solen row is the Cannon Ball participant, linked once.
    assert has_element?(
             view,
             ~s(#portfolio-link-cannon-ball-elementary[href="/school-goals/cannon-ball-elementary"]),
             "Cannon Ball"
           )

    assert has_element?(view, "#portfolio-row-cannon-ball-elementary", "Workbook row “Solen”")
    assert has_element?(view, "#cannon-ball-elementary-spr_26-systems", "1.20")
    refute html =~ "portfolio-row-solen"
    # Solen High School is Cannon Ball's building: never a portfolio row, and
    # (November 13, 2026) not listed on the main dashboard; it is a subtab
    # inside Cannon Ball's pages.
    refute has_element?(view, "#portfolio-row-solen-high-school")
    refute has_element?(view, "#school-solen-high-school")
    refute html =~ ~s(href="/school-goals/solen-high-school")

    # Participant navigation is kept; buildings only inside their participant.
    assert has_element?(view, "#nd-tab-fort-yates-ms")
    assert has_element?(view, "#participant-drayton-public-school-district")
    assert has_element?(view, "#school-drayton-public-school-district")
    refute has_element?(view, "#school-drayton-elementary")
  end

  test "a single-school viewer sees only that participant's row and figures", %{
    conn: conn,
    org: org
  } do
    viewer = user!(org, :school_leader)
    membership!(viewer, school!(org, "oberon-elementary"), :viewer, org)

    {:ok, view, html} = live(log_in(conn, viewer), "/school-goals")

    assert has_element?(view, "#portfolio-row-oberon-elementary")
    refute html =~ "portfolio-row-fort-yates-ms"
    refute html =~ "portfolio-row-solen"
    refute html =~ "Ft Yates"
    assert has_element?(view, "#portfolio-average", "of 1 participant shown")
  end

  test "a building-only member gets the participant row without its figures", %{
    conn: conn,
    org: org
  } do
    member = user!(org, :school_leader)
    membership!(member, school!(org, "drayton-elementary"), :viewer, org)

    {:ok, view, _html} = live(log_in(conn, member), "/school-goals")

    assert has_element?(
             view,
             "#portfolio-row-drayton-public-school-district[data-status=no_access]",
             "isn't available to you"
           )

    assert has_element?(
             view,
             ~s(#portfolio-link-drayton-public-school-district[href="/school-goals/drayton-elementary"])
           )

    refute has_element?(view, "#portfolio-average")
  end
end
