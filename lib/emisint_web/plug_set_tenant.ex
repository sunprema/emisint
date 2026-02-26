defmodule EmisintWeb.SetTenant do
  @behaviour Plug
  import Plug.Conn
  alias Ash.PlugHelpers

  def init(opts), do: opts

  # Authenticated request; user has organization_id as tenant
  def call(
        %{assigns: %{current_user: %{organization_id: organization_id} = current_user}} = conn,
        _opts
      )
      when not is_nil(organization_id) do
    scope = %Emisint.Scope{current_user: current_user, current_tenant: organization_id}

    conn
    |> assign(:current_tenant, organization_id)
    |> PlugHelpers.set_tenant(organization_id)
    |> assign(:current_tenant, organization_id)
    |> assign(:scope, scope)
  end

  # No tenant yet (e.g., org-selection pages)
  def call(conn, _opts) do
    assign(conn, :current_tenant, nil)
  end
end
