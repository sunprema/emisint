defmodule EmisintWeb.Admin.OrganizationsLive do
  use EmisintWeb, :live_view

  on_mount {EmisintWeb.LiveUserAuth, :live_user_required}

  @org_types [{"EMO (Management Company)", :emo}, {"Authorizer", :authorizer}]

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if user.role != :system_admin do
      {:ok, push_navigate(socket, to: ~p"/dashboard")}
    else
      {:ok, socket |> assign(org_types: @org_types, show_new_org_modal: false, form_errors: []) |> load_data()}
    end
  end

  defp load_data(socket) do
    actor = socket.assigns.current_user
    orgs = Emisint.Accounts.list_organizations!(actor: actor, authorize?: false)
    users = Emisint.Accounts.list_users!(actor: actor, authorize?: false)
    assign(socket, organizations: orgs, users: users)
  end

  def handle_event("open_new_org", _params, socket) do
    {:noreply, assign(socket, show_new_org_modal: true, form_errors: [])}
  end

  def handle_event("close_new_org", _params, socket) do
    {:noreply, assign(socket, show_new_org_modal: false, form_errors: [])}
  end

  def handle_event("create_org", %{"name" => name, "type" => type, "slug" => slug}, socket) do
    actor = socket.assigns.current_user

    case Emisint.Accounts.create_organization(
           %{name: name, type: String.to_existing_atom(type), slug: slug},
           actor: actor,
           authorize?: false
         ) do
      {:ok, org} ->
        {:noreply,
         socket
         |> assign(show_new_org_modal: false, form_errors: [])
         |> load_data()
         |> put_flash(:info, "Organization \"#{org.name}\" created.")}

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        {:noreply, assign(socket, form_errors: Enum.map(errors, &Exception.message/1))}

      {:error, _} ->
        {:noreply, assign(socket, form_errors: ["An unexpected error occurred."])}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="p-6 max-w-5xl mx-auto space-y-8">

        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold">Organizations</h1>
            <p class="text-base-content/60 text-sm mt-1">Create and manage organizations.</p>
          </div>
          <button class="btn btn-primary btn-sm" phx-click="open_new_org">
            <.icon name="hero-plus" class="size-4" /> New Organization
          </button>
        </div>

        <div class="bg-base-100 border border-base-200 rounded-xl overflow-hidden">
          <table class="table table-zebra w-full">
            <thead>
              <tr class="bg-base-200/60 text-base-content/70 text-xs uppercase tracking-wide">
                <th>Name</th>
                <th>Slug</th>
                <th>Type</th>
                <th>Status</th>
                <th>Users</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={org <- @organizations} class="hover:bg-base-200/30">
                <td class="font-medium">
                  <.link navigate={~p"/admin/organizations/#{org.id}"} class="hover:underline">
                    {org.name}
                  </.link>
                </td>
                <td class="text-base-content/50 font-mono text-sm">{org.slug}</td>
                <td>
                  <span class={["badge badge-sm", type_badge_class(org.type)]}>
                    {format_type(org.type)}
                  </span>
                </td>
                <td>
                  <span class={["badge badge-sm", if(org.active, do: "badge-success", else: "badge-ghost")]}>
                    {if org.active, do: "Active", else: "Inactive"}
                  </span>
                </td>
                <td class="text-base-content/60 text-sm">
                  {Enum.count(@users, &(&1.organization_id == org.id))}
                </td>
              </tr>
            </tbody>
          </table>
          <div :if={@organizations == []} class="text-center py-12 text-base-content/40">
            No organizations yet. Create one to get started.
          </div>
        </div>
      </div>

      <%!-- New Organization Modal --%>
      <div
        :if={@show_new_org_modal}
        class="modal modal-open"
        phx-window-keydown="close_new_org"
        phx-key="Escape"
      >
        <div class="modal-box max-w-sm">
          <h3 class="font-bold text-lg mb-4">New Organization</h3>

          <div :if={@form_errors != []} class="alert alert-error mb-4 text-sm">
            <ul class="list-disc list-inside">
              <li :for={err <- @form_errors}>{err}</li>
            </ul>
          </div>

          <form phx-submit="create_org" class="space-y-4">
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Name</span></label>
              <input type="text" name="name" class="input input-bordered w-full" required />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Slug</span></label>
              <input
                type="text"
                name="slug"
                class="input input-bordered w-full font-mono"
                placeholder="e.g. great-lakes-emo"
                required
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Type</span></label>
              <select name="type" class="select select-bordered w-full">
                <option :for={{label, value} <- @org_types} value={value}>{label}</option>
              </select>
            </div>
            <div class="modal-action">
              <button type="button" class="btn btn-ghost" phx-click="close_new_org">Cancel</button>
              <button type="submit" class="btn btn-primary">Create</button>
            </div>
          </form>
        </div>
        <div class="modal-backdrop" phx-click="close_new_org"></div>
      </div>
    </Layouts.app>
    """
  end

  defp format_type(:emo), do: "EMO"
  defp format_type(:authorizer), do: "Authorizer"

  defp type_badge_class(:emo), do: "badge-primary"
  defp type_badge_class(:authorizer), do: "badge-secondary"
  defp type_badge_class(_), do: "badge-ghost"
end
