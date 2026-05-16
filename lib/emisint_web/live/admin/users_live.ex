defmodule EmisintWeb.Admin.UsersLive do
  use EmisintWeb, :live_view

  on_mount {EmisintWeb.LiveUserAuth, :live_user_required}

  @roles [
    {"EMO Admin", :emo_admin},
    {"School Leader", :school_leader},
    {"Authorizer Liaison", :authorizer_liaison},
    {"System Admin", :system_admin}
  ]

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if user.role not in [:system_admin] do
      {:ok, push_navigate(socket, to: ~p"/authorizer-portfolio")}
    else
      users = Emisint.Accounts.list_users!(actor: user, authorize?: false)
      {:ok, assign(socket, users: users, editing_user: nil, roles: @roles)}
    end
  end

  def handle_event("edit_role", %{"id" => id}, socket) do
    user = Enum.find(socket.assigns.users, &(to_string(&1.id) == id))
    {:noreply, assign(socket, editing_user: user)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_user: nil)}
  end

  def handle_event("save_role", %{"role" => role}, socket) do
    actor = socket.assigns.current_user
    user = socket.assigns.editing_user

    case Emisint.Accounts.update_user_role(user, %{role: String.to_existing_atom(role)},
           actor: actor,
           authorize?: false
         ) do
      {:ok, updated} ->
        users =
          Enum.map(socket.assigns.users, fn u ->
            if u.id == updated.id, do: updated, else: u
          end)

        {:noreply,
         socket
         |> assign(users: users, editing_user: nil)
         |> put_flash(:info, "Role updated successfully.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update role.")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="p-6 max-w-5xl mx-auto">
        <div class="mb-6">
          <h1 class="text-2xl font-bold">User Management</h1>
          <p class="text-base-content/60 text-sm mt-1">Manage user roles across the platform.</p>
        </div>

        <div class="bg-base-100 border border-base-200 rounded-xl overflow-hidden">
          <table class="table table-zebra w-full">
            <thead>
              <tr class="bg-base-200/60 text-base-content/70 text-xs uppercase tracking-wide">
                <th>Email</th>
                <th>Role</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={user <- @users} class="hover:bg-base-200/30">
                <td class="font-medium">{user.email |> to_string()}</td>
                <td>
                  <span class={["badge badge-sm", role_badge_class(user.role)]}>
                    {format_role(user.role)}
                  </span>
                </td>
                <td class="text-right">
                  <button
                    class="btn btn-xs btn-ghost"
                    phx-click="edit_role"
                    phx-value-id={user.id}
                  >
                    <.icon name="hero-pencil-square" class="size-4" /> Edit Role
                  </button>
                </td>
              </tr>
            </tbody>
          </table>

          <div :if={@users == []} class="text-center py-12 text-base-content/40">
            No users found.
          </div>
        </div>
      </div>

      <%!-- Role edit modal --%>
      <div
        :if={@editing_user}
        class="modal modal-open"
        phx-window-keydown="cancel_edit"
        phx-key="Escape"
      >
        <div class="modal-box max-w-sm">
          <h3 class="font-bold text-lg mb-1">Edit Role</h3>
          <p class="text-sm text-base-content/60 mb-4">
            {@editing_user.email |> to_string()}
          </p>

          <form phx-submit="save_role">
            <div class="form-control mb-6">
              <label class="label">
                <span class="label-text font-medium">Role</span>
              </label>
              <select name="role" class="select select-bordered w-full">
                <option
                  :for={{label, value} <- @roles}
                  value={value}
                  selected={@editing_user.role == value}
                >
                  {label}
                </option>
              </select>
            </div>

            <div class="modal-action">
              <button type="button" class="btn btn-ghost" phx-click="cancel_edit">Cancel</button>
              <button type="submit" class="btn btn-primary">Save</button>
            </div>
          </form>
        </div>
        <div class="modal-backdrop" phx-click="cancel_edit"></div>
      </div>
    </Layouts.app>
    """
  end

  defp format_role(:emo_admin), do: "EMO Admin"
  defp format_role(:school_leader), do: "School Leader"
  defp format_role(:authorizer_liaison), do: "Authorizer Liaison"
  defp format_role(:system_admin), do: "System Admin"
  defp format_role(role), do: role |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp role_badge_class(:system_admin), do: "badge-error"
  defp role_badge_class(:emo_admin), do: "badge-primary"
  defp role_badge_class(:authorizer_liaison), do: "badge-warning"
  defp role_badge_class(_), do: "badge-ghost"
end
