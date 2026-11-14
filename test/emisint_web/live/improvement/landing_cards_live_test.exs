defmodule EmisintWeb.Improvement.LandingCardsLiveTest do
  @moduledoc """
  The main `/school-goals` dashboard lists the eight participants only
  (November 13, 2026): building links appear only inside a participant's
  pages (District overview and building subtabs, with sibling navigation).
  Direct building URLs and building-only access are unchanged.
  """
  use EmisintWeb.ConnCase, async: true

  import Emisint.ImprovementFixtures
  import Phoenix.LiveViewTest

  alias Emisint.Improvement.{Pilot, Seeds}

  setup %{conn: conn} do
    org =
      seeded_organization!(
        name: "Landing cards",
        schools: Seeds.available_schools(),
        workbook_ratings?: true
      )

    %{org: org, conn: conn, admin_conn: log_in(conn, user!(org, :emo_admin))}
  end

  defp building_slugs,
    do:
      for(
        m <- Seeds.available_schools(),
        function_exported?(m, :participant, 0),
        do: m.school().slug
      )

  test "eight participant cards, each linking to its main page, and no building links", %{
    admin_conn: conn
  } do
    {:ok, view, html} = live(conn, "/school-goals")

    cards =
      Regex.scan(~r/id="participant-([a-z0-9-]+)"/, html)
      |> Enum.map(&List.last/1)
      |> Enum.reject(&String.ends_with?(&1, "-provisional"))

    assert cards == Enum.map(Pilot.roster(), & &1.slug)
    assert length(cards) == 8

    for slug <- cards,
        do:
          assert(
            has_element?(
              view,
              ~s(#participant-#{slug} #school-#{slug}[href="/school-goals/#{slug}"])
            )
          )

    assert length(building_slugs()) == 10

    for slug <- building_slugs() do
      refute html =~ ~s(href="/school-goals/#{slug}"), slug
      refute has_element?(view, "#school-#{slug}"), slug
    end
  end

  test "inside a district: overview and building subtabs, with sibling navigation", %{
    admin_conn: conn
  } do
    {:ok, district, _html} = live(conn, "/school-goals/warwick-public-school-district")

    for {slug, label} <- [
          {"warwick-public-school-district", "District overview"},
          {"warwick-elementary", "Elementary School"},
          {"warwick-middle-school", "Middle School"},
          {"warwick-high-school", "High School"}
        ],
        do: assert(has_element?(district, "#participant-nav-#{slug}", label))

    {:ok, middle, _html} =
      district
      |> element("#participant-nav-warwick-middle-school")
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(middle, ~s(#participant-nav-warwick-middle-school[aria-current="page"]))

    {:ok, high, _html} =
      middle
      |> element("#participant-nav-warwick-high-school")
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(high, ~s(#participant-nav-warwick-high-school[aria-current="page"]))
    assert has_element?(high, ~s(#nd-tab-warwick-public-school-district[aria-current="page"]))

    {:ok, back, _html} =
      high
      |> element("#participant-nav-warwick-public-school-district")
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(back, "h1", "Warwick Public School District")
  end

  test "Solen High School appears only inside Cannon Ball's pages", %{admin_conn: conn} do
    {:ok, landing, html} = live(conn, "/school-goals")
    refute html =~ "solen-high-school"

    assert has_element?(
             landing,
             "#participant-cannon-ball-elementary #school-cannon-ball-elementary"
           )

    {:ok, cb, _html} = live(conn, "/school-goals/cannon-ball-elementary")
    assert has_element?(cb, "#participant-nav-solen-high-school", "Solen High School")
    # Payment stays with the participant record; the building has none.
    assert has_element?(cb, "#payment-card")

    {:ok, solen, _html} = live(conn, "/school-goals/solen-high-school")
    refute has_element?(solen, "#payment-card")
    assert has_element?(solen, ~s(#participant-nav-solen-high-school[aria-current="page"]))
  end

  test "direct building URLs and building-only members still work", %{conn: conn, org: org} do
    member = user!(org, :school_leader)
    membership!(member, school!(org, "dunseith-high-school"), :viewer, org)
    member_conn = log_in(conn, member)

    {:ok, landing, html} = live(member_conn, "/school-goals")
    # One card for the participant, linking to the building they can read.
    assert has_element?(
             landing,
             ~s(#participant-link-dunseith-public-school-district[href="/school-goals/dunseith-high-school"])
           )

    refute html =~ ~s(id="school-dunseith-high-school")

    {:ok, page, _html} = live(member_conn, "/school-goals/dunseith-high-school")
    assert has_element?(page, "h1", "Dunseith High School")

    # The district and sibling building stay unreadable for this member.
    assert {:error, {:live_redirect, %{to: "/school-goals"}}} =
             live(member_conn, "/school-goals/dunseith-public-school-district")

    assert {:error, {:live_redirect, %{to: "/school-goals"}}} =
             live(member_conn, "/school-goals/dunseith-elementary")
  end
end
