defmodule EmisintWeb.PendingLive do
  use EmisintWeb, :live_view

  on_mount {EmisintWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    # If somehow a user with an org lands here, send them to the dashboard
    if user.organization_id do
      {:ok, push_navigate(socket, to: ~p"/dashboard")}
    else
      {:ok, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 flex items-center justify-center p-6">
      <div class="max-w-md w-full text-center space-y-6">
        <div class="mx-auto size-16 rounded-full bg-warning/10 flex items-center justify-center">
          <.icon name="hero-clock" class="size-8 text-warning" />
        </div>

        <div class="space-y-2">
          <h1 class="text-2xl font-bold">Account Pending Setup</h1>
          <p class="text-base-content/60">
            Your account has been created but hasn't been assigned to an organization yet.
            Please contact your system administrator to complete setup.
          </p>
        </div>

        <div class="bg-base-100 border border-base-200 rounded-xl p-4 text-sm text-base-content/60">
          Signed in as <span class="font-medium text-base-content">{@current_user.email |> to_string()}</span>
        </div>

        <.link href={~p"/sign-out"} class="btn btn-ghost btn-sm">
          Sign Out
        </.link>
      </div>
    </div>
    """
  end
end
