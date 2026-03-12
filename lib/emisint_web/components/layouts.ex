defmodule EmisintWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use EmisintWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :any, default: nil, doc: "the authenticated user struct, if any"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open min-h-screen">
      <input id="main-drawer" type="checkbox" class="drawer-toggle" />

      <%!-- Page content --%>
      <div class="drawer-content flex flex-col">
        <%!-- Mobile top navbar --%>
        <div class="navbar bg-base-300 lg:hidden sticky top-0 z-20">
          <label for="main-drawer" class="btn btn-square btn-ghost drawer-button">
            <.icon name="hero-bars-3" class="size-6" />
          </label>
          <span class="font-bold ml-2 text-lg">Emisint APM</span>
        </div>

        <%!-- Main content area --%>
        <main class="flex-1 p-4 sm:p-6 lg:p-8">
          {render_slot(@inner_block)}
        </main>
      </div>

      <%!-- Sidebar --%>
      <div class="drawer-side z-30">
        <label for="main-drawer" class="drawer-overlay" aria-label="close sidebar"></label>
        <aside class="w-64 min-h-full bg-base-200 flex flex-col border-r border-base-300">
          <%!-- Logo --%>
          <div class="p-4 border-b border-base-300">
            <.link navigate={~p"/dashboard"} class="flex items-center gap-2">
              <.icon name="hero-academic-cap" class="size-7 text-primary" />
              <div>
                <div class="font-bold text-base leading-tight">Emisint APM</div>
                <div class="text-xs text-base-content/50">Academic Performance</div>
              </div>
            </.link>
          </div>

          <%!-- Navigation --%>
          <nav class="flex-1 p-3">
            <ul class="menu menu-sm gap-0.5">
              <li :if={@current_user && @current_user.role == :system_admin}>
                <.link navigate={~p"/admin/organizations"} class="flex items-center gap-2">
                  <.icon name="hero-building-office" class="size-4" /> Organizations
                </.link>
              </li>
              <li>
                <.link navigate={~p"/dashboard"} class="flex items-center gap-2">
                  <.icon name="hero-squares-2x2" class="size-4" /> Portfolio
                </.link>
              </li>
              <li>
                <.link navigate={~p"/health-scores"} class="flex items-center gap-2">
                  <.icon name="hero-chart-bar" class="size-4" /> Health Scores
                </.link>
              </li>
              <li>
                <.link navigate={~p"/mde"} class="flex items-center gap-2">
                  <.icon name="hero-chart-bar-square" class="size-4" /> MDE Data
                </.link>
              </li>
              <li>
                <.link navigate={~p"/mde/entities"} class="flex items-center gap-2">
                  <.icon name="hero-building-office-2" class="size-4" /> Entity Master
                </.link>
              </li>
              <li :if={@current_user && @current_user.role in [:emo_admin, :system_admin]}>
                <.link navigate={~p"/admin/import"} class="flex items-center gap-2">
                  <.icon name="hero-arrow-up-tray" class="size-4" /> Data Import
                </.link>
              </li>
              <li :if={@current_user && @current_user.role == :system_admin}>
                <.link navigate={~p"/admin/import/history"} class="flex items-center gap-2">
                  <.icon name="hero-clock" class="size-4" /> Import History
                </.link>
              </li>
              <li :if={@current_user && @current_user.role == :system_admin}>
                <.link navigate={~p"/admin/users"} class="flex items-center gap-2">
                  <.icon name="hero-users" class="size-4" /> Users
                </.link>
              </li>
              <li>
                <.link navigate={~p"/settings"} class="flex items-center gap-2">
                  <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
                </.link>
              </li>
            </ul>
          </nav>

          <%!-- User profile + sign-out + theme --%>
          <div class="border-t border-base-300">
            <%!-- Profile card --%>
            <div :if={@current_user} class="p-3">
              <div class="flex items-center gap-3 p-3 bg-base-300/50">
                <div class="size-9 rounded-full bg-primary text-primary-content flex items-center justify-center shrink-0 text-xs font-bold">
                  {String.first(String.upcase(@current_user.email |> to_string() || "?"))}
                </div>
                <div class="overflow-hidden flex-1 min-w-0">
                  <div class="text-sm font-medium truncate">{@current_user.email |> to_string()}</div>
                  <div class="text-xs text-base-content/50 mt-0.5">
                    {format_role(@current_user.role)}
                  </div>
                </div>
              </div>
            </div>

            <%!-- Sign out --%>
            <div class="px-3 pb-3 space-y-1">
              <.link
                :if={@current_user && @current_user.role == :system_admin}
                navigate={~p"/admin/context"}
                class="flex items-center gap-2 w-full px-3 py-2 text-sm text-base-content/60 hover:text-base-content hover:bg-base-300/50 transition-colors"
              >
                <.icon name="hero-arrows-right-left" class="size-4" /> Switch Org
              </.link>
              <.link
                href={~p"/sign-out"}
                class="flex items-center gap-2 w-full px-3 py-2 text-sm text-base-content/60 hover:text-base-content hover:bg-base-300/50 transition-colors"
              >
                <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Sign Out
              </.link>

            </div>
          </div>
        </aside>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  defp format_role(nil), do: ""

  defp format_role(role) when is_atom(role) do
    role
    |> to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
