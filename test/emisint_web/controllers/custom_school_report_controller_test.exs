defmodule EmisintWeb.CustomSchoolReportControllerTest do
  use EmisintWeb.ConnCase, async: false

  test "PDF endpoint requires authentication", %{conn: conn} do
    conn = get(conn, "/mde/reports/school.pdf?building=00000&year=24%20-%2025%20School%20Year")
    assert redirected_to(conn) == "/sign-in"
  end

  test "invalid templates return a controlled client error", %{conn: conn} do
    conn =
      authenticated_controller_conn(conn)
      |> EmisintWeb.CustomSchoolReportController.show(%{
        "building" => "00000",
        "year" => "24 - 25 School Year",
        "template" => "invalid"
      })

    assert conn.status == 400
    assert conn.resp_body == "Unknown school report template"
  end

  test "invalid sections return a controlled client error", %{conn: conn} do
    conn =
      authenticated_controller_conn(conn)
      |> EmisintWeb.CustomSchoolReportController.show(%{
        "building" => "00000",
        "year" => "24 - 25 School Year",
        "sections" => "key_metrics,sample_data"
      })

    assert conn.status == 400
    assert conn.resp_body == "Unknown school report section"
  end

  defp authenticated_controller_conn(conn) do
    scope = %Emisint.Scope{
      current_tenant: Ash.UUID.generate(),
      current_user: %{id: Ash.UUID.generate(), role: :system_admin, organization_id: nil}
    }

    conn
    |> assign(:current_user, scope.current_user)
    |> assign(:scope, scope)
  end
end
