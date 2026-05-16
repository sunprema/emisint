defmodule EmisintWeb.Admin.OrganizationShowLive do
  use EmisintWeb, :live_view

  on_mount {EmisintWeb.LiveUserAuth, :live_user_required}

  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    if user.role != :system_admin do
      {:ok, push_navigate(socket, to: ~p"/authorizer-portfolio")}
    else
      {:ok, socket |> load_data(id) |> assign(confirm_remove_user: nil, show_assign_modal: false, form_errors: [])}
    end
  end

  defp load_data(socket, org_id) do
    actor = socket.assigns.current_user

    org_task = Task.async(fn -> Emisint.Accounts.get_organization!(org_id, actor: actor, authorize?: false) end)
    users_task = Task.async(fn -> Emisint.Accounts.list_users!(actor: actor, authorize?: false) end)

    org = Task.await(org_task)
    all_users = Task.await(users_task)

    org_users = Enum.filter(all_users, &(&1.organization_id == org.id))
    unassigned_users = Enum.filter(all_users, &is_nil(&1.organization_id))
    assign(socket, organization: org, users: org_users, unassigned_users: unassigned_users, org_id: org_id)
  end

  def handle_event("open_assign", _params, socket) do
    {:noreply, assign(socket, show_assign_modal: true, form_errors: [])}
  end

  def handle_event("close_assign", _params, socket) do
    {:noreply, assign(socket, show_assign_modal: false, form_errors: [])}
  end

  def handle_event("assign_user", %{"user_id" => ""}, socket) do
    {:noreply, assign(socket, form_errors: ["Please select a user."])}
  end

  def handle_event("assign_user", %{"user_id" => user_id}, socket) do
    actor = socket.assigns.current_user
    org = socket.assigns.organization
    user = Enum.find(socket.assigns.unassigned_users, &(to_string(&1.id) == user_id))

    case Emisint.Accounts.assign_organization(
           user,
           %{organization_id: org.id, role: user.role, school_id: user.school_id},
           actor: actor,
           authorize?: false
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(show_assign_modal: false, form_errors: [])
         |> load_data(socket.assigns.org_id)
         |> put_flash(:info, "User assigned to #{org.name}.")}

      {:error, _} ->
        {:noreply, assign(socket, form_errors: ["Failed to assign user."])}
    end
  end

  def handle_event("confirm_remove", %{"user-id" => user_id}, socket) do
    user = Enum.find(socket.assigns.users, &(to_string(&1.id) == user_id))
    {:noreply, assign(socket, confirm_remove_user: user)}
  end

  def handle_event("cancel_remove", _params, socket) do
    {:noreply, assign(socket, confirm_remove_user: nil)}
  end

  def handle_event("remove_user", _params, socket) do
    actor = socket.assigns.current_user
    user = socket.assigns.confirm_remove_user

    case Emisint.Accounts.assign_organization(
           user,
           %{organization_id: nil, role: user.role, school_id: nil},
           actor: actor,
           authorize?: false
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(confirm_remove_user: nil)
         |> load_data(socket.assigns.org_id)
         |> put_flash(:info, "#{user.email} removed from organization.")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(confirm_remove_user: nil)
         |> put_flash(:error, "Failed to remove user.")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="p-6 max-w-4xl mx-auto space-y-6">

        <%!-- Back + Header --%>
        <div>
          <.link navigate={~p"/admin/organizations"} class="text-sm text-base-content/50 hover:text-base-content flex items-center gap-1 mb-4">
            <.icon name="hero-arrow-left" class="size-4" /> Organizations
          </.link>

          <div class="flex items-start justify-between">
            <div>
              <h1 class="text-2xl font-bold">{@organization.name}</h1>
              <div class="flex items-center gap-3 mt-1">
                <span class="font-mono text-sm text-base-content/50">{@organization.slug}</span>
                <span class={["badge badge-sm", type_badge_class(@organization.type)]}>
                  {format_type(@organization.type)}
                </span>
                <span class={["badge badge-sm", if(@organization.active, do: "badge-success", else: "badge-ghost")]}>
                  {if @organization.active, do: "Active", else: "Inactive"}
                </span>
              </div>
            </div>
          </div>
        </div>

        <%!-- Users section --%>
        <div class="bg-base-100 border border-base-200 rounded-xl overflow-hidden">
          <div class="px-4 py-3 border-b border-base-200 flex items-center justify-between">
            <div class="flex items-center gap-2">
              <h2 class="font-semibold">Users</h2>
              <span class="badge badge-ghost badge-sm">{length(@users)}</span>
            </div>
            <button class="btn btn-xs btn-primary" phx-click="open_assign">
              <.icon name="hero-user-plus" class="size-4" /> Assign User
            </button>
          </div>

          <table :if={@users != []} class="table table-zebra w-full">
            <thead>
              <tr class="bg-base-200/60 text-base-content/70 text-xs uppercase tracking-wide">
                <th>Email</th>
                <th>Role</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={u <- @users} class="hover:bg-base-200/30">
                <td class="font-medium">{u.email |> to_string()}</td>
                <td>
                  <span class={["badge badge-sm", role_badge_class(u.role)]}>
                    {format_role(u.role)}
                  </span>
                </td>
                <td class="text-right">
                  <button
                    class="btn btn-xs btn-ghost text-error hover:bg-error/10"
                    phx-click="confirm_remove"
                    phx-value-user-id={u.id}
                  >
                    <.icon name="hero-user-minus" class="size-4" /> Remove
                  </button>
                </td>
              </tr>
            </tbody>
          </table>

          <div :if={@users == []} class="text-center py-12 text-base-content/40">
            No users assigned to this organization.
          </div>
        </div>
      </div>

      <%!-- Assign User Modal --%>
      <div
        :if={@show_assign_modal}
        class="modal modal-open"
        phx-window-keydown="close_assign"
        phx-key="Escape"
      >
        <div class="modal-box max-w-sm">
          <h3 class="font-bold text-lg mb-1">Assign User</h3>
          <p class="text-sm text-base-content/60 mb-4">
            Add a user to <span class="font-medium text-base-content">{@organization.name}</span>.
          </p>

          <div :if={@form_errors != []} class="alert alert-error mb-4 text-sm">
            <ul class="list-disc list-inside">
              <li :for={err <- @form_errors}>{err}</li>
            </ul>
          </div>

          <div :if={@unassigned_users == []} class="text-sm text-base-content/50 py-4 text-center">
            No unassigned users available.
          </div>

          <form :if={@unassigned_users != []} phx-submit="assign_user" class="space-y-4">
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">User</span></label>
              <select name="user_id" class="select select-bordered w-full">
                <option value="">— Select a user —</option>
                <option :for={u <- @unassigned_users} value={u.id}>
                  {u.email |> to_string()}
                </option>
              </select>
            </div>
            <div class="modal-action">
              <button type="button" class="btn btn-ghost" phx-click="close_assign">Cancel</button>
              <button type="submit" class="btn btn-primary">Assign</button>
            </div>
          </form>

          <div :if={@unassigned_users == []} class="modal-action">
            <button type="button" class="btn btn-ghost" phx-click="close_assign">Close</button>
          </div>
        </div>
        <div class="modal-backdrop" phx-click="close_assign"></div>
      </div>

      <%!-- Confirm remove modal --%>
      <div
        :if={@confirm_remove_user}
        class="modal modal-open"
        phx-window-keydown="cancel_remove"
        phx-key="Escape"
      >
        <div class="modal-box max-w-sm">
          <h3 class="font-bold text-lg mb-2">Remove User?</h3>
          <p class="text-sm text-base-content/60">
            <span class="font-medium text-base-content">
              {@confirm_remove_user.email |> to_string()}
            </span>
            will be unassigned from <span class="font-medium text-base-content">{@organization.name}</span>
            and will lose access to the platform until reassigned.
          </p>
          <div class="modal-action">
            <button class="btn btn-ghost" phx-click="cancel_remove">Cancel</button>
            <button class="btn btn-error" phx-click="remove_user">Remove</button>
          </div>
        </div>
        <div class="modal-backdrop" phx-click="cancel_remove"></div>
      </div>
    </Layouts.app>
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

  defp format_role(:emo_admin), do: "EMO Admin"
  defp format_role(:school_leader), do: "School Leader"
  defp format_role(:authorizer_liaison), do: "Authorizer Liaison"
  defp format_role(:system_admin), do: "System Admin"
  defp format_role(r), do: r |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp role_badge_class(:system_admin), do: "badge-error"
  defp role_badge_class(:emo_admin), do: "badge-primary"
  defp role_badge_class(:authorizer_liaison), do: "badge-warning"
  defp role_badge_class(_), do: "badge-ghost"
end
