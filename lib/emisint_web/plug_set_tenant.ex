defmodule EmisintWeb.SetTenant do
  @behaviour Plug
  import Plug.Conn
  alias Ash.PlugHelpers

  def init(opts), do: opts

  # Authenticated request; user has organization_id as tenant
  def call(%{assigns: %{current_user: current_user}} = conn, _opts) do
    tenant = Emisint.Scope.tenant_for(current_user, get_session(conn))

    if tenant do
      scope = %Emisint.Scope{current_user: current_user, current_tenant: tenant}

      conn
      |> PlugHelpers.set_tenant(tenant)
      |> assign(:current_tenant, tenant)
      |> assign(:scope, scope)
    else
      assign(conn, :current_tenant, nil)
    end
  end

  # No tenant yet (e.g., org-selection pages)
  def call(conn, _opts) do
    assign(conn, :current_tenant, nil)
  end
end
