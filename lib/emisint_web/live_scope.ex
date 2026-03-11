defmodule EmisintWeb.LiveScope do
  import Phoenix.Component
  use EmisintWeb, :verified_routes

  @doc """
  This is a hook to set the scope in the socket. Should be called after LiveUserAuth hook
  """
  def on_mount(:default, _params, session, socket) do
    user = socket.assigns[:current_user]

    tenant =
      if user.role == :system_admin do
        session["admin_org_id"] || user.organization_id
      else
        user.organization_id
      end

    if is_nil(tenant) do
      redirect_to = if user.role == :system_admin, do: ~p"/admin/context", else: ~p"/pending"
      {:halt, Phoenix.LiveView.redirect(socket, to: redirect_to)}
    else
      scope = %Emisint.Scope{current_user: user, current_tenant: tenant}
      {:cont, assign(socket, :scope, scope)}
    end
  end
end
