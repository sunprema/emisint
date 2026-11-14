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

    # A registered school outside the pilot, to show the filter still applies.
    non_pilot_school!(org)

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

    assert has_element?(
             view,
             "#school-valley-middle-school",
             "Grand Forks Public School District"
           )

    # Participant cards link to the main record; buildings only appear inside it.
    assert has_element?(view, "#school-drayton-public-school-district")

    for slug <- ~w(drayton-elementary drayton-high-school warwick-middle-school),
        do: refute(has_element?(view, "#school-#{slug}"))

    refute has_element?(view, "#school-synthetic-non-pilot-school")
  end

  test "every verified record stays listable without the pilot filter", %{admin: admin} do
    scope = %Emisint.Scope{current_user: admin, current_tenant: admin.organization_id}

    slugs = scope |> Dashboard.list_schools() |> Enum.map(& &1.slug)

    assert Enum.sort(slugs) ==
             Enum.sort(
               ["synthetic-non-pilot-school"] ++
                 Enum.map(Seeds.available_schools(), & &1.school().slug)
             )

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
    # The workbook's 18-month terms apply to every participant (November 13, 2026).
    assert has_element?(view, "#payment-formal-heading", "Estimated payment — provisional terms")

    assert has_element?(
             view,
             "#payment-card-note",
             "Preview only; final payment depends on formal review."
           )

    assert has_element?(view, "#payment-card-terms", "Provisional terms")
    assert has_element?(view, "#payment-review_36m", "30% / 70%")
    assert has_element?(view, "#payment-review_18m", "$70,000.00")
    assert has_element?(view, "#payment-review_36m", "Needs confirmation")
    assert has_element?(view, "#payment-terms", "Performance-Based Payment")
    refute render(view) =~ "$35,000"

    assert has_element?(
             view,
             "#payment-review_18m-estimate",
             "Awaiting review: 21 review ratings"
           )
  end

  test "Valley shows N/A ratings and qualitative targets as written", %{conn: conn, admin: admin} do
    {:ok, view, _html} =
      live(log_in(conn, admin), "/school-goals/valley-middle-school?period=spr_26")

    assert has_element?(view, "#rating-G1-M3", "N/A")
    assert has_element?(view, "#metric-G7-M2 [data-target-value]", "Created")
    assert has_element?(view, "#metric-G1-M2 [data-target-value]", "> 50%")
    assert has_element?(view, "#annual-2030-2031-ela", "No matching results in the imported data")
  end
end
