defmodule EmisintWeb.Improvement.SchoolPageSectionsLiveTest do
  @moduledoc """
  Collapsible detail sections on the school and district pages: workbook
  goals, official state results and the North Dakota comparison. Official
  state results are open by default and the others closed (November 13,
  2026); the name, navigation, key summary and import/PDF actions stay
  visible; the open state is kept in the URL across period and filter
  changes; Expand all / Collapse all; the PDF is always the full report.
  """
  # Never concurrent with other ND Insights imports (see Emisint.NdInsightsFixtures).
  use EmisintWeb.ConnCase, async: true, group: :nd_insights_import

  import Emisint.ImprovementFixtures
  import Emisint.NdInsightsFixtures
  import Phoenix.LiveViewTest

  alias Emisint.Improvement.Seeds
  alias Emisint.Reports.School.NdFirstSchoolPdf

  @fixtures Path.expand("../../../fixtures/nd_insights", __DIR__)
  @fort_yates "/school-goals/fort-yates-ms"

  setup %{conn: conn} do
    org =
      seeded_organization!(
        name: "ND First page sections",
        schools: Seeds.available_schools(),
        workbook_ratings?: true
      )

    files = ~w(
      Insights-AssessmentPerformance-CSV-2024-2025-v20251113.csv
      Insights-GrowthRate-CSV-2024-2025-v20251113.csv
      Insights-Engagement-Emotional-All-CSV-v20251202.csv
    )

    import_insights!(Enum.map(files, &Path.join(@fixtures, &1)),
      institution_ids: ["4300429212"],
      tenant: org.id
    )

    admin = user!(org, :emo_admin)

    %{
      org: org,
      admin: admin,
      conn: log_in(conn, admin),
      sys_conn: log_in(conn, user!(nil, :system_admin), %{"admin_org_id" => org.id})
    }
  end

  defp expanded?(view, id),
    do:
      has_element?(view, ~s(##{id}-toggle[aria-expanded="true"])) and
        not has_element?(view, "##{id}-body[hidden]")

  defp collapsed?(view, id),
    do:
      has_element?(view, ~s(##{id}-toggle[aria-expanded="false"])) and
        has_element?(view, "##{id}-body[hidden]")

  test "state results open by default, the other sections closed; header items stay visible", %{
    sys_conn: conn
  } do
    {:ok, view, _html} = live(conn, @fort_yates)

    assert expanded?(view, "state-results")
    assert collapsed?(view, "goals")
    assert collapsed?(view, "nd-comparison")

    for id <- ~w(goals state-results nd-comparison),
        do:
          assert(has_element?(view, ~s(##{id}-toggle[type="button"][aria-controls="#{id}-body"])))

    assert has_element?(view, "h1", "Fort Yates Middle School")
    assert has_element?(view, "#nd-tab-fort-yates-ms")
    assert has_element?(view, "#period")
    assert has_element?(view, "#download-pdf")
    assert has_element?(view, "#seasonal-average-systems")
    assert has_element?(view, "#payment-card")
    # The import action sits in the header, outside the collapsible body.
    assert has_element?(view, "#state-results #nd-import-link")
    refute has_element?(view, "#state-results-body #nd-import-link")
    # Filters live inside their section.
    assert has_element?(view, "#state-results-body #state-filters")

    # Short summaries from existing data.
    assert has_element?(view, "#goals-summary", "goals ·")
    assert has_element?(view, "#goals-summary", "ratings: Systems")
    assert has_element?(view, "#state-results-summary", "2024-2025 · Combined · All students")
    assert has_element?(view, "#state-results-summary", "goal comparisons")
    assert has_element?(view, "#nd-comparison-summary", "2024-2025")

    refute has_element?(view, ~s(#section-controls-collapse[disabled]))
    refute has_element?(view, ~s(#section-controls-expand[disabled]))
  end

  test "the user's choice survives period and filter changes", %{conn: conn} do
    {:ok, view, _html} = live(conn, @fort_yates)

    view |> element("#goals-toggle") |> render_click()
    assert_patch(view, "#{@fort_yates}?open=goals%2Cstate")
    assert expanded?(view, "goals")
    assert expanded?(view, "state-results")

    # Collapsing the state results is kept.
    view |> element("#state-results-toggle") |> render_click()
    assert_patch(view, "#{@fort_yates}?open=goals")
    assert collapsed?(view, "state-results")

    view |> form("#period-select", %{period: "spr_26"}) |> render_change()
    assert_patch(view, "#{@fort_yates}?open=goals&period=spr_26")
    assert expanded?(view, "goals")
    assert collapsed?(view, "state-results")
    assert has_element?(view, "#goals-summary", "Spr '26 ratings")

    # Closing the last open section is explicit too ("none"), not the default.
    view |> element("#goals-toggle") |> render_click()
    assert_patch(view, "#{@fort_yates}?open=none&period=spr_26")
    for id <- ~w(goals state-results nd-comparison), do: assert(collapsed?(view, id))

    view |> element("#state-results-toggle") |> render_click()
    view |> form("#state-filters", %{state_type: "Reg"}) |> render_change()
    assert expanded?(view, "state-results")
    assert collapsed?(view, "goals")
    assert has_element?(view, "#state-results-summary", "Standard")
    assert collapsed?(view, "nd-comparison")
  end

  test "explicit section state in a URL is kept", %{conn: conn} do
    {:ok, view, _html} = live(conn, "#{@fort_yates}?open=goals")
    assert expanded?(view, "goals")
    assert collapsed?(view, "state-results")

    {:ok, view, _html} = live(conn, "#{@fort_yates}?open=nd")
    assert expanded?(view, "nd-comparison")
    assert collapsed?(view, "state-results")
  end

  test "Collapse all stays collapsed after filter changes and reloads; Expand all", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "#{@fort_yates}?period=sum_26")

    view |> element("#section-controls-collapse") |> render_click()
    assert_patch(view, "#{@fort_yates}?open=none&period=sum_26")
    for id <- ~w(goals state-results nd-comparison), do: assert(collapsed?(view, id))
    assert has_element?(view, ~s(#section-controls-collapse[disabled]))

    view |> form("#period-select", %{period: "spr_26"}) |> render_change()
    assert_patch(view, "#{@fort_yates}?open=none&period=spr_26")
    view |> form("#state-filters", %{state_type: "Reg"}) |> render_change()
    for id <- ~w(goals state-results nd-comparison), do: assert(collapsed?(view, id))

    # A reload of the same URL.
    {:ok, reloaded, _html} = live(conn, "#{@fort_yates}?open=none&period=spr_26")
    for id <- ~w(goals state-results nd-comparison), do: assert(collapsed?(reloaded, id))

    reloaded |> element("#section-controls-expand") |> render_click()
    assert_patch(reloaded, "#{@fort_yates}?open=goals%2Cstate%2Cnd%2Cpayment&period=spr_26")
    for id <- ~w(goals state-results nd-comparison), do: assert(expanded?(reloaded, id))
    assert has_element?(reloaded, ~s(#section-controls-expand[disabled]))
  end

  test "school-to-school and district/building navigation opens state results", %{conn: conn} do
    {:ok, view, _html} = live(conn, "#{@fort_yates}?open=none")

    # A main tab goes to the other school's page with no section state: the default.
    {:ok, oberon, _html} =
      view |> element("#nd-tab-oberon-elementary") |> render_click() |> follow_redirect(conn)

    assert expanded?(oberon, "state-results")
    assert collapsed?(oberon, "goals")

    {:ok, district, _html} = live(conn, "/school-goals/drayton-public-school-district")
    assert expanded?(district, "state-results")

    {:ok, building, _html} =
      district
      |> element("#participant-nav-drayton-high-school")
      |> render_click()
      |> follow_redirect(conn)

    refute has_element?(building, "#goals-toggle")
    assert expanded?(building, "state-results")
    assert has_element?(building, "#state-results-body #state-results-empty")

    {:ok, back, _html} =
      building
      |> element("#participant-nav-drayton-public-school-district")
      |> render_click()
      |> follow_redirect(conn)

    assert expanded?(back, "state-results")
    assert collapsed?(back, "goals")

    {:ok, solen, _html} = live(conn, "/school-goals/solen-high-school")
    assert expanded?(solen, "state-results")
  end

  test "goal mappings and colors are unchanged inside collapsed sections", %{conn: conn} do
    {:ok, view, _html} = live(conn, "#{@fort_yates}?state_year=2024-2025")

    # Fort Yates's workbook comparison marks are rendered (in the hidden body).
    assert has_element?(view, ~s(#state-results-body [data-goal="G2-M1"][data-kind="workbook"]))
    assert has_element?(view, "#state-results-body #achievement-goal-notes")
  end

  test "the PDF is the full report whatever is collapsed", %{conn: conn, admin: admin, org: org} do
    {:ok, view, _html} = live(conn, "#{@fort_yates}?open=goals")

    href =
      view
      |> element("#download-pdf")
      |> render()
      |> then(&Regex.run(~r/href="([^"]+)"/, &1))
      |> List.last()

    refute href =~ "open="

    scope = %Emisint.Scope{current_user: admin, current_tenant: org.id}
    {:ok, data, _name} = NdFirstSchoolPdf.build(scope, "fort-yates-ms", %{"open" => ""})
    assert length(data.goals) == 4
    assert data.state.has_data
    assert data.state.achievement != []

    assert {:ok, "%PDF" <> _, _} = NdFirstSchoolPdf.generate(scope, "fort-yates-ms", %{})
  end
end
