defmodule EmisintWeb.RequireAuthenticatedUser do
  @moduledoc "Requires the browser session to contain an authenticated user."

  import Phoenix.Controller
  import Plug.Conn
  use EmisintWeb, :verified_routes

  def init(opts), do: opts

  def call(%{assigns: %{current_user: current_user}} = conn, _opts) when not is_nil(current_user),
    do: conn

  def call(conn, _opts) do
    conn
    |> redirect(to: ~p"/sign-in")
    |> halt()
  end
end
