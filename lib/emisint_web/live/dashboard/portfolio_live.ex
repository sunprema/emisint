defmodule EmisintWeb.Dashboard.PortfolioLive do
  use EmisintWeb, :live_view

  on_mount {EmisintWeb.LiveUserAuth, :live_user_required}
  on_mount {EmisintWeb.LiveScope, :default}

  def mount(_params, _session, socket) do
    org =
      if connected?(socket) do
        Ash.get!(Emisint.Accounts.Organization, socket.assigns.scope.current_tenant,
          authorize?: false
        )
      end

    {:ok, assign(socket, page_title: "Portfolio Overview", org: org)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-6xl mx-auto space-y-6">
        <div class="flex items-center gap-4">
          <div class="p-2.5 bg-primary/10 border border-primary/20">
            <.icon name="hero-squares-2x2" class="size-6 text-primary" />
          </div>
          <div>
            <h1 class="text-2xl font-bold tracking-tight">Portfolio Overview</h1>
            <p :if={@org} class="text-sm text-base-content/50 mt-0.5">{@org.name}</p>
          </div>
        </div>

        <div class="bg-base-100 border border-base-200 flex flex-col items-center justify-center py-16 text-center">
          <div class="p-3 bg-base-200 mb-3">
            <.icon name="hero-building-office" class="size-7 text-base-content/25" />
          </div>
          <p class="text-sm font-medium text-base-content/40">Portfolio view coming soon</p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
