defmodule EmisintWeb.Improvement.NavigationTest do
  @moduledoc """
  ND FIRST navigation (November 8, 2026): one main tab per participant (Fort
  Yates, Oberon, Valley Middle, Drayton, Dunseith, Mandaree, Warwick), a
  participant navigation (District overview + Elementary/Middle/High School)
  on district participants and their buildings, the participant's tab
  highlighted on its buildings, and only destinations the user can read.
  """
  use EmisintWeb.ConnCase, async: true

  import Emisint.ImprovementFixtures
  import Phoenix.LiveViewTest

  alias Emisint.Improvement.Seeds

  @participants ~w(fort-yates-ms oberon-elementary valley-middle-school drayton-public-school-district dunseith-public-school-district mandaree-public-school-district warwick-public-school-district cannon-ball-elementary)

  @districts %{
    "drayton-public-school-district" => [
      {"drayton-elementary", "Elementary School"},
      {"drayton-high-school", "High School"}
    ],
    "dunseith-public-school-district" => [
      {"dunseith-elementary", "Elementary School"},
      {"dunseith-high-school", "High School"}
    ],
    "mandaree-public-school-district" => [
      {"mandaree-elementary", "Elementary School"},
      {"mandaree-high-school", "High School"}
    ],
    "warwick-public-school-district" => [
      {"warwick-elementary", "Elementary School"},
      {"warwick-middle-school", "Middle School"},
      {"warwick-high-school", "High School"}
    ]
  }

  setup do
    org = seeded_organization!(name: "ND First navigation", schools: Seeds.available_schools())
    %{org: org, admin: user!(org, :emo_admin)}
  end

  defp tab_ids(html), do: Regex.scan(~r/id="nd-tab-([a-z0-9-]+)"/, html) |> Enum.map(&List.last/1)

  defp nav_ids(html),
    do: Regex.scan(~r/id="participant-nav-([a-z0-9-]+)"/, html) |> Enum.map(&List.last/1)

  test "one main tab per participant, in order, with no building tabs", %{
    conn: conn,
    admin: admin
  } do
    {:ok, view, html} = live(log_in(conn, admin), "/school-goals")

    assert tab_ids(html) == @participants

    for slug <- @participants do
      assert has_element?(view, ~s(#nd-tab-#{slug}[href="/school-goals/#{slug}"]))
    end

    assert has_element?(view, "#nd-tab-valley-middle-school", "Valley Middle")
    # Cannon Ball (the workbook's "Solen" participant) comes last.
    assert has_element?(view, "#nd-tab-cannon-ball-elementary", "Cannon Ball")

    for {_district, buildings} <- @districts, {slug, _} <- buildings do
      refute has_element?(view, "#nd-tab-#{slug}")
    end

    # Landing cards are grouped by participant, buildings inside their district.
    assert Regex.scan(~r/id="participant-([a-z0-9-]+)"/, html)
           |> Enum.map(&List.last/1)
           |> Enum.reject(&String.ends_with?(&1, "-provisional")) ==
             @participants

    # Buildings aren't listed on the main dashboard (November 13, 2026).
    assert has_element?(
             view,
             ~s(#participant-warwick-public-school-district #school-warwick-public-school-district[href="/school-goals/warwick-public-school-district"])
           )

    refute has_element?(view, "#school-warwick-middle-school")
    refute html =~ ~s(href="/school-goals/warwick-middle-school")

    assert has_element?(view, "#participant-warwick-public-school-district-provisional")
    refute has_element?(view, "#participant-drayton-public-school-district-provisional")
  end

  test "single-building participants have their tab highlighted and no participant nav", %{
    conn: conn,
    admin: admin
  } do
    for slug <- ~w(fort-yates-ms oberon-elementary valley-middle-school) do
      {:ok, view, _} = live(log_in(conn, admin), "/school-goals/#{slug}")
      assert has_element?(view, ~s(#nd-tab-#{slug}[aria-current="page"]))
      assert length(Regex.scan(~r/aria-current="page"/, render(view))) == 1
      refute has_element?(view, "#participant-nav")
    end
  end

  test "each district shows District overview and its buildings, overview current", %{
    conn: conn,
    admin: admin
  } do
    for {district, buildings} <- @districts do
      {:ok, view, html} = live(log_in(conn, admin), "/school-goals/#{district}")

      assert has_element?(view, ~s(#nd-tab-#{district}[aria-current="page"]))
      assert nav_ids(html) -- ["provisional"] == [district | Enum.map(buildings, &elem(&1, 0))]

      assert has_element?(
               view,
               ~s(#participant-nav-#{district}[aria-current="page"][href="/school-goals/#{district}"]),
               "District overview"
             )

      for {slug, label} <- buildings do
        assert has_element?(
                 view,
                 ~s(#participant-nav-#{slug}[href="/school-goals/#{slug}"]),
                 label
               )

        refute has_element?(view, ~s(#participant-nav-#{slug}[aria-current]))
      end
    end
  end

  test "a direct link to any building keeps its participant tab and marks the building", %{
    conn: conn,
    admin: admin
  } do
    for {district, buildings} <- @districts, {slug, label} <- buildings do
      {:ok, view, html} = live(log_in(conn, admin), "/school-goals/#{slug}")

      assert has_element?(view, ~s(#nd-tab-#{district}[aria-current="page"])), slug
      assert has_element?(view, ~s(#participant-nav-#{slug}[aria-current="page"]), label)

      assert has_element?(
               view,
               ~s(#participant-nav-#{district}[href="/school-goals/#{district}"]),
               "District overview"
             )

      refute has_element?(view, ~s(#participant-nav-#{district}[aria-current]))
      # Exactly one tab and one participant page are current.
      assert length(Regex.scan(~r/aria-current="page"/, html)) == 2
    end
  end

  test "Warwick keeps its provisional scope label in the navigation", %{conn: conn, admin: admin} do
    for slug <-
          ~w(warwick-public-school-district warwick-elementary warwick-middle-school warwick-high-school) do
      {:ok, view, _} = live(log_in(conn, admin), "/school-goals/#{slug}")
      assert has_element?(view, "#participant-nav-provisional", "Workbook scope provisional")
    end

    {:ok, drayton, _} = live(log_in(conn, admin), "/school-goals/drayton-high-school")
    refute has_element?(drayton, "#participant-nav-provisional")
  end

  test "a Fort Yates-only viewer sees only Fort Yates", %{conn: conn, org: org} do
    viewer = user!(org, :school_leader)
    membership!(viewer, school!(org, "fort-yates-ms"), :viewer, org)

    {:ok, landing, html} = live(log_in(conn, viewer), "/school-goals")
    assert tab_ids(html) == ["fort-yates-ms"]
    assert has_element?(landing, "#school-fort-yates-ms")
    refute has_element?(landing, "#participant-drayton-public-school-district")

    {:ok, view, html} = live(log_in(conn, viewer), "/school-goals/fort-yates-ms")
    assert tab_ids(html) == ["fort-yates-ms"]
    assert has_element?(view, ~s(#nd-tab-fort-yates-ms[aria-current="page"]))
    refute has_element?(view, "#participant-nav")

    assert {:error, {_, %{to: "/school-goals"}}} =
             live(log_in(conn, viewer), "/school-goals/drayton-elementary")
  end

  test "a building-only member reaches the participant through its building", %{
    conn: conn,
    org: org
  } do
    member = user!(org, :school_leader)
    membership!(member, school!(org, "drayton-elementary"), :viewer, org)

    {:ok, view, html} = live(log_in(conn, member), "/school-goals/drayton-elementary")

    # The Drayton tab opens the readable building, not the unreadable district.
    assert tab_ids(html) == ["drayton-public-school-district"]

    assert has_element?(
             view,
             ~s(#nd-tab-drayton-public-school-district[href="/school-goals/drayton-elementary"][aria-current="page"])
           )

    # Only the readable page is listed: no District overview or High School.
    assert nav_ids(html) == ["drayton-elementary"]

    assert has_element?(
             view,
             ~s(#participant-nav-drayton-elementary[aria-current="page"]),
             "Elementary School"
           )

    {:ok, landing, _} = live(log_in(conn, member), "/school-goals")

    # The card links to the one page this member can read, without listing buildings.
    assert has_element?(
             landing,
             ~s(#participant-drayton-public-school-district #participant-link-drayton-public-school-district[href="/school-goals/drayton-elementary"]),
             "Drayton"
           )

    refute has_element?(landing, "#school-drayton-elementary")
    refute has_element?(landing, "#school-drayton-public-school-district")
    refute has_element?(landing, "#school-drayton-high-school")
  end
end
