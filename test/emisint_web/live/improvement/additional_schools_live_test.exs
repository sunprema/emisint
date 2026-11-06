defmodule EmisintWeb.Improvement.AdditionalSchoolsLiveTest do
  use EmisintWeb.ConnCase, async: true

  import Emisint.ImprovementFixtures
  import Phoenix.LiveViewTest

  alias Emisint.Improvement.{Dashboard, Seeds}

  setup do
    org =
      seeded_organization!(
        name: "All ND First",
        schools: Seeds.available_schools(),
        workbook_ratings?: true
      )

    %{org: org, admin: user!(org, :emo_admin)}
  end

  test "the ND First landing page lists only the configured pilot schools", %{
    conn: conn,
    admin: admin
  } do
    {:ok, view, _html} = live(log_in(conn, admin), "/school-goals")

    assert has_element?(view, "#school-fort-yates-ms", "Ft Yates Public School District")
    assert has_element?(view, "#school-fort-yates-ms", "Grades 5-8")
    assert has_element?(view, "#school-oberon-elementary", "Oberon Public School District")
    refute has_element?(view, "#school-valley-middle-school")
  end

  test "schools deferred for expansion stay seeded and listable without the pilot filter", %{
    admin: admin
  } do
    scope = %Emisint.Scope{current_user: admin, current_tenant: admin.organization_id}

    assert scope |> Dashboard.list_schools() |> Enum.map(& &1.slug) ==
             ~w(fort-yates-ms oberon-elementary valley-middle-school)

    assert scope
           |> Dashboard.list_schools(institution_ids: ["1800189752"])
           |> Enum.map(&{&1.slug, &1.district_name, &1.grade_span}) ==
             [{"valley-middle-school", "Grand Forks Public School District", "6-8"}]
  end

  test "Oberon shows its own targets verbatim, flags dates and cites its own cells", %{
    conn: conn,
    admin: admin
  } do
    {:ok, view, _html} =
      live(log_in(conn, admin), "/school-goals/oberon-elementary?period=sum_26")

    assert has_element?(view, "#metric-G1-M1 [data-target-value]", "16%")
    assert has_element?(view, "#metric-G3-M2 [data-target-value]", "60-64%")
    assert has_element?(view, "#metric-G4-M7 [data-target-value]", "Needs confirmation")
    assert has_element?(view, "#metric-G4-M4 [data-target-value]", "50")

    # Goal 1 is headed "18-Month Review Rating"; Goal 2 is "Target Check".
    refute has_element?(view, "#review-column-note-goal-1")
    assert has_element?(view, "#review-column-note-goal-2", "Oberon Goals!I12")

    assert has_element?(
             view,
             "#review-column-note-goal-2",
             "Goal 1 uses “18-Month Review Rating” (I3)"
           )

    assert has_element?(view, "#review-column-note-goal-2", "Performance-Based Payment!C6")

    # Workbook N/A and scores are imported per school.
    assert has_element?(view, "#rating-G1-M1", "Implementation on Track")
    assert has_element?(view, "#payment-card", "Not configured")
    assert has_element?(view, "#payment-card", "Estimated payment — not configured")
    assert has_element?(view, "#payment-card", "No payment terms are set for this school.")
    refute has_element?(view, "#payment-card", "Provisional, not an actual payment")
    assert has_element?(view, "#payment-review_36m", "30% / 70%")
    # Only Fort Yates has the provisional allocations; nothing is assumed here.
    assert has_element?(view, "#payment-terms", "Not configured")
    refute render(view) =~ "$35,000"
    assert has_element?(view, "#payment-review_18m-estimate", "Not configured")
  end

  test "Valley shows N/A ratings and qualitative targets as written", %{conn: conn, admin: admin} do
    {:ok, view, _html} =
      live(log_in(conn, admin), "/school-goals/valley-middle-school?period=spr_26")

    assert has_element?(view, "#rating-G1-M3", "N/A")
    assert has_element?(view, "#metric-G7-M2 [data-target-value]", "Created")
    assert has_element?(view, "#metric-G1-M2 [data-target-value]", "> 50%")
    assert has_element?(view, "#annual-2030-2031-ela", "Not yet published")
  end
end
