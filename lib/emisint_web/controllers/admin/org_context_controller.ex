defmodule EmisintWeb.Admin.OrgContextController do
  use EmisintWeb, :controller

  def set(conn, %{"org_id" => org_id}) do
    conn
    |> put_session(:admin_org_id, org_id)
    |> redirect(to: ~p"/authorizer-portfolio")
  end
end
