defmodule EmisintWeb.LiveScope do
  import Phoenix.Component
  use EmisintWeb, :verified_routes

  @doc """
  This is a hook to set the scope in the socket. Should be called after LiveUserAuth hook
  """
  def on_mount(:default, _params, _session, socket) do
    scope = %Emisint.Scope{
      current_user: socket.assigns[:current_user],
      current_tenant: socket.assigns.current_user.organization_id
    }

    {:cont,
     socket
     |> assign(:scope, scope)}
  end
end
