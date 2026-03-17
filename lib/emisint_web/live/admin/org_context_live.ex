defmodule EmisintWeb.Admin.OrgContextLive do
  use EmisintWeb, :live_view

  on_mount {EmisintWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if user.role != :system_admin do
      {:ok, push_navigate(socket, to: ~p"/pending")}
    else
      orgs = Emisint.Accounts.list_organizations!(actor: user, authorize?: false)
      {:ok, assign(socket, organizations: orgs)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 flex items-center justify-center p-6">
      <div class="max-w-md w-full space-y-6">
        <div class="text-center space-y-2">
          <div class="mx-auto size-14 rounded-full bg-primary/10 flex items-center justify-center">
            <.icon name="hero-building-office" class="size-7 text-primary" />
          </div>
          <h1 class="text-2xl font-bold">Select Organization Context</h1>
          <p class="text-base-content/60 text-sm">
            Choose which organization you want to operate as for this session.
          </p>
        </div>

        <div class="bg-base-100 border border-base-200 rounded-xl overflow-hidden">
          <form action={~p"/admin/context"} method="post">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <ul class="divide-y divide-base-200">
              <li :for={org <- @organizations}>
                <button
                  type="submit"
                  name="org_id"
                  value={org.id}
                  class="w-full flex items-center justify-between px-4 py-3 hover:bg-base-200/50 text-left transition-colors"
                >
                  <div>
                    <div class="font-medium">{org.name}</div>
                    <div class="text-xs text-base-content/50 font-mono">{org.slug}</div>
                  </div>
                  <div class="flex items-center gap-2">
                    <span class={["badge badge-sm", type_badge_class(org.type)]}>
                      {format_type(org.type)}
                    </span>
                    <.icon name="hero-chevron-right" class="size-4 text-base-content/30" />
                  </div>
                </button>
              </li>
            </ul>
            <div :if={@organizations == []} class="text-center py-10 text-base-content/40 text-sm">
              No organizations exist yet.
              <.link navigate={~p"/admin/organizations"} class="link link-primary block mt-2">
                Create one
              </.link>
            </div>
          </form>
        </div>

        <div class="text-center text-xs text-base-content/40">
          Signed in as {@current_user.email |> to_string()} &middot;
          <.link href={~p"/sign-out"} class="hover:text-base-content">Sign Out</.link>
        </div>
      </div>
    </div>
    """
  end

  defp format_type(:emo), do: "EMO"
  defp format_type(:authorizer), do: "Authorizer"
  defp format_type(:admin), do: "Admin"
  defp format_type(:self_managed), do: "Self-Managed"

  defp type_badge_class(:emo), do: "badge-primary"
  defp type_badge_class(:authorizer), do: "badge-secondary"
  defp type_badge_class(:admin), do: "badge-neutral"
  defp type_badge_class(_), do: "badge-ghost"
end
