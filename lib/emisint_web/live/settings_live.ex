defmodule EmisintWeb.SettingsLive do
  use EmisintWeb, :live_view

  on_mount {EmisintWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Settings")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="p-6 max-w-2xl mx-auto space-y-6">
        <div>
          <h1 class="text-2xl font-bold">Settings</h1>
          <p class="text-base-content/60 text-sm mt-1">Manage your preferences.</p>
        </div>

        <div class="bg-base-100 border border-base-200 rounded-xl divide-y divide-base-200">
          <%!-- Theme --%>
          <div class="flex items-center justify-between px-5 py-4">
            <div>
              <div class="font-medium text-sm">Theme</div>
              <div class="text-xs text-base-content/50 mt-0.5">Choose between system, light, or dark mode.</div>
            </div>
            <Layouts.theme_toggle />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
