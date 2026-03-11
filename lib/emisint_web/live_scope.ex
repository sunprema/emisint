defmodule EmisintWeb.LiveScope do
  import Phoenix.Component
  use EmisintWeb, :verified_routes

  @doc """
  This is a hook to set the scope in the socket. Should be called after LiveUserAuth hook
  """
  def on_mount(:default, _params, _session, socket) do
    user = socket.assigns[:current_user]

    if is_nil(user.organization_id) do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/pending")}
    else
      scope = %Emisint.Scope{
        current_user: user,
        current_tenant: user.organization_id
      }

      {:cont, assign(socket, :scope, scope)}
    end
  end
end
