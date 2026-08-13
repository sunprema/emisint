defmodule EmisintWeb.Reports.SchoolReportBuilderLiveTest do
  use EmisintWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Emisint.Accounts.{Organization, User}

  defp authenticated_conn(conn, role) do
    organization =
      Ash.create!(
        Organization,
        %{name: "Report Test Org", type: :emo, slug: "report-test-#{System.unique_integer()}"},
        authorize?: false
      )

    user =
      Ash.create!(
        User,
        %{
          email: "report-#{System.unique_integer()}@example.com",
          password: "Password123!",
          password_confirmation: "Password123!"
        },
        action: :register_with_password,
        authorize?: false
      )

    user =
      Ash.update!(user, %{organization_id: organization.id, role: role},
        action: :assign_organization,
        authorize?: false
      )

    conn =
      conn
      |> init_test_session(%{})
      |> AshAuthentication.Phoenix.Plug.store_in_session(user)

    {conn, organization}
  end

  test "user selects a template and any full-report section for one report", %{conn: conn} do
    {conn, _organization} = authenticated_conn(conn, :emo_admin)

    {:ok, view, _html} =
      live(conn, "/mde/reports/school/12345?year=24%20-%2025%20School%20Year")

    assert has_element?(view, "#school-report-builder")
    assert has_element?(view, "#report-template-compact_portrait")
    assert has_element?(view, "#report-template-detailed_landscape")
    assert has_element?(view, "#report-section-school_profile input[checked]")
    assert has_element?(view, "#report-section-mission_statement input[checked]")
    assert has_element?(view, "#report-section-board_roster", "Data unavailable")
    assert has_element?(view, "#report-section-financial_testing_appendix input[checked]")

    view |> element("#report-template-detailed_landscape") |> render_click()
    view |> element("#report-section-mission_statement input") |> render_click()

    assert has_element?(
             view,
             "#generate-custom-report[href*='template=detailed_landscape']"
           )

    refute has_element?(view, "#report-section-mission_statement input[checked]")
    assert render(view) =~ "school_profile"
    assert render(view) =~ "financial_testing_appendix"
  end

  test "compact portrait and the complete catalog are selected initially", %{conn: conn} do
    {conn, _organization} = authenticated_conn(conn, :school_leader)

    {:ok, view, _html} =
      live(conn, "/mde/reports/school/12345?year=24%20-%2025%20School%20Year")

    html = render(view)
    assert html =~ "template=compact_portrait"
    assert html =~ "school_profile"
    assert html =~ "financial_testing_appendix"
    assert has_element?(view, "#report-section-academic_compliance_appendix input[checked]")
  end
end
