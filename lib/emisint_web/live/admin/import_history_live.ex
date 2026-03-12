defmodule EmisintWeb.Admin.ImportHistoryLive do
  use EmisintWeb, :live_view

  require Ash.Query

  alias Emisint.Assessments.MdeImportLog

  @pubsub_topics ~w(mde_import entity_master_import enrollment_import sat_import)

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Enum.each(@pubsub_topics, &Phoenix.PubSub.subscribe(Emisint.PubSub, &1))
    end

    socket =
      socket
      |> assign(:page_title, "Import History")
      |> assign(:filter_type, "all")
      |> assign(:filter_status, "all")
      |> assign(:logs, load_logs("all", "all"))

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub — any MDE import event triggers a refresh
  # ---------------------------------------------------------------------------

  def handle_info({event, _payload}, socket)
      when event in [
             :mde_import_completed,
             :mde_import_failed,
             :entity_master_import_completed,
             :entity_master_import_failed,
             :enrollment_import_completed,
             :enrollment_import_failed,
             :sat_import_completed,
             :sat_import_failed
           ] do
    logs = load_logs(socket.assigns.filter_type, socket.assigns.filter_status)
    {:noreply, assign(socket, :logs, logs)}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  def handle_event("filter_type", %{"type" => type}, socket) do
    logs = load_logs(type, socket.assigns.filter_status)
    {:noreply, socket |> assign(:filter_type, type) |> assign(:logs, logs)}
  end

  def handle_event("filter_status", %{"status" => status}, socket) do
    logs = load_logs(socket.assigns.filter_type, status)
    {:noreply, socket |> assign(:filter_status, status) |> assign(:logs, logs)}
  end

  def handle_event("refresh", _params, socket) do
    logs = load_logs(socket.assigns.filter_type, socket.assigns.filter_status)
    {:noreply, assign(socket, :logs, logs)}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-7xl mx-auto space-y-6">
        <%!-- Page header --%>
        <div class="flex items-center justify-between gap-4">
          <div class="flex items-center gap-4">
            <div class="p-2.5 bg-primary/10 border border-primary/20">
              <.icon name="hero-clock" class="size-6 text-primary" />
            </div>
            <div>
              <h1 class="text-2xl font-bold tracking-tight">Import History</h1>
              <p class="text-sm text-base-content/50 mt-0.5">
                All MDE data uploads — real-time status updates
              </p>
            </div>
          </div>
          <button
            phx-click="refresh"
            class="btn btn-sm btn-ghost gap-2 text-base-content/60"
          >
            <.icon name="hero-arrow-path" class="size-4" /> Refresh
          </button>
        </div>

        <%!-- Summary stats --%>
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
          <.stat_card
            label="Total Imports"
            value={length(@logs)}
            icon="hero-inbox-arrow-down"
            color="primary"
          />
          <.stat_card
            label="Completed"
            value={Enum.count(@logs, &(&1.status == :completed))}
            icon="hero-check-circle"
            color="success"
          />
          <.stat_card
            label="Processing"
            value={Enum.count(@logs, &(&1.status == :processing))}
            icon="hero-arrow-path"
            color="info"
          />
          <.stat_card
            label="Failed"
            value={Enum.count(@logs, &(&1.status == :failed))}
            icon="hero-x-circle"
            color="error"
          />
        </div>

        <%!-- Filters --%>
        <div class="flex flex-wrap items-center gap-3">
          <span class="text-sm font-medium text-base-content/60">Filter:</span>

          <%!-- Type filter --%>
          <div class="flex gap-1">
            <button
              :for={
                {label, value} <- [
                  {"All Types", "all"},
                  {"MDE", "mde"},
                  {"Entity Master", "entity_master"},
                  {"Enrollment", "enrollment"},
                  {"SAT", "sat"}
                ]
              }
              phx-click="filter_type"
              phx-value-type={value}
              class={[
                "btn btn-xs",
                @filter_type == value && "btn-primary",
                @filter_type != value && "btn-ghost"
              ]}
            >
              {label}
            </button>
          </div>

          <div class="divider divider-horizontal mx-0"></div>

          <%!-- Status filter --%>
          <div class="flex gap-1">
            <button
              :for={
                {label, value} <- [
                  {"All Status", "all"},
                  {"Processing", "processing"},
                  {"Completed", "completed"},
                  {"Failed", "failed"}
                ]
              }
              phx-click="filter_status"
              phx-value-status={value}
              class={[
                "btn btn-xs",
                @filter_status == value && "btn-primary",
                @filter_status != value && "btn-ghost"
              ]}
            >
              {label}
            </button>
          </div>

          <span class="ml-auto text-xs text-base-content/40">
            {length(@logs)} record{if length(@logs) != 1, do: "s", else: ""}
          </span>
        </div>

        <%!-- Table --%>
        <div class="bg-base-100 border border-base-200 overflow-hidden">
          <div
            :if={@logs == []}
            class="flex flex-col items-center justify-center py-20 text-center"
          >
            <div class="p-4 bg-base-200 mb-4">
              <.icon name="hero-inbox" class="size-8 text-base-content/25" />
            </div>
            <p class="font-medium text-base-content/50">No imports found</p>
            <p class="text-sm text-base-content/35 mt-1">
              {if @filter_type != "all" or @filter_status != "all",
                do: "Try adjusting your filters.",
                else: "Uploads will appear here once submitted."}
            </p>
          </div>

          <div :if={@logs != []} class="overflow-x-auto">
            <table class="table w-full">
              <thead>
                <tr class="text-xs text-base-content/50 border-b border-base-200 bg-base-50">
                  <th class="px-4 py-3 font-medium">Type</th>
                  <th class="px-4 py-3 font-medium">File</th>
                  <th class="px-4 py-3 font-medium">Size</th>
                  <th class="px-4 py-3 font-medium">Status</th>
                  <th class="px-4 py-3 font-medium">Records</th>
                  <th class="px-4 py-3 font-medium">Errors</th>
                  <th class="px-4 py-3 font-medium">School Year</th>
                  <th class="px-4 py-3 font-medium">Details</th>
                  <th class="px-4 py-3 font-medium">Uploaded By</th>
                  <th class="px-4 py-3 font-medium">Date</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-base-200">
                <tr
                  :for={log <- @logs}
                  class={[
                    "hover:bg-base-50 transition-colors text-sm",
                    log.status == :failed && "bg-error/5"
                  ]}
                >
                  <%!-- Type badge --%>
                  <td class="px-4 py-3">
                    <span class={[
                      "badge badge-sm font-medium whitespace-nowrap",
                      log.import_type == :mde && "badge-warning",
                      log.import_type == :entity_master && "badge-info",
                      log.import_type == :enrollment && "badge-success",
                      log.import_type == :sat && "badge-secondary"
                    ]}>
                      {import_type_label(log.import_type)}
                    </span>
                  </td>

                  <%!-- Filename --%>
                  <td class="px-4 py-3">
                    <span
                      class="font-mono text-xs text-base-content/80 max-w-[220px] block truncate"
                      title={log.original_filename}
                    >
                      {log.original_filename}
                    </span>
                  </td>

                  <%!-- File size --%>
                  <td class="px-4 py-3 text-base-content/60 whitespace-nowrap">
                    {format_bytes(log.file_size_bytes)}
                  </td>

                  <%!-- Status --%>
                  <td class="px-4 py-3">
                    <.import_status_badge status={log.status} />
                  </td>

                  <%!-- Records processed --%>
                  <td class="px-4 py-3 tabular-nums text-right">
                    {if log.records_processed,
                      do: format_number(log.records_processed),
                      else: "—"}
                  </td>

                  <%!-- Error count --%>
                  <td class={[
                    "px-4 py-3 tabular-nums text-right",
                    log.error_count && log.error_count > 0 && "text-error font-medium"
                  ]}>
                    {if log.error_count, do: log.error_count, else: "—"}
                  </td>

                  <%!-- School year --%>
                  <td class="px-4 py-3 text-base-content/60 whitespace-nowrap">
                    {log.school_year || "—"}
                  </td>

                  <%!-- Details (metadata + error message) --%>
                  <td class="px-4 py-3 max-w-[200px]">
                    <div :if={log.error_message} class="text-xs text-error truncate" title={log.error_message}>
                      {log.error_message}
                    </div>
                    <div
                      :if={log.status == :completed && map_size(log.metadata || %{}) > 0}
                      class="flex flex-wrap gap-x-2 gap-y-0.5"
                    >
                      <span :if={log.metadata["isds"]} class="text-xs text-base-content/50">
                        {log.metadata["isds"]} ISDs
                      </span>
                      <span :if={log.metadata["districts"]} class="text-xs text-base-content/50">
                        {log.metadata["districts"]} districts
                      </span>
                      <span :if={log.metadata["buildings"]} class="text-xs text-base-content/50">
                        {log.metadata["buildings"]} buildings
                      </span>
                      <span :if={log.metadata["duration_ms"]} class="text-xs text-base-content/40">
                        {format_duration(log.metadata["duration_ms"])}
                      </span>
                    </div>
                    <span
                      :if={
                        is_nil(log.error_message) &&
                          map_size(log.metadata || %{}) == 0
                      }
                      class="text-base-content/30"
                    >
                      —
                    </span>
                  </td>

                  <%!-- Uploaded by --%>
                  <td class="px-4 py-3 text-xs text-base-content/60">
                    {if log.uploaded_by, do: log.uploaded_by.email, else: "—"}
                  </td>

                  <%!-- Date --%>
                  <td class="px-4 py-3 text-xs text-base-content/50 whitespace-nowrap">
                    {format_datetime(log.inserted_at)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :icon, :string, required: true
  attr :color, :string, required: true

  def stat_card(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-200 p-4 flex items-center gap-4">
      <div class={["p-2.5", "bg-#{@color}/10"]}>
        <.icon name={@icon} class={["size-5", "text-#{@color}"]} />
      </div>
      <div>
        <div class="text-2xl font-bold tabular-nums">{@value}</div>
        <div class="text-xs text-base-content/50 mt-0.5">{@label}</div>
      </div>
    </div>
    """
  end

  def import_status_badge(assigns) do
    ~H"""
    <span :if={@status == :uploading} class="badge badge-ghost badge-sm">Uploading</span>
    <span :if={@status == :processing} class="badge badge-info badge-sm gap-1">
      <span class="loading loading-spinner loading-xs"></span> Processing
    </span>
    <span :if={@status == :completed} class="badge badge-success badge-sm">Completed</span>
    <span :if={@status == :failed} class="badge badge-error badge-sm">Failed</span>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp load_logs(type_filter, status_filter) do
    MdeImportLog
    |> Ash.Query.for_read(:list_recent, %{limit: 200})
    |> maybe_filter_type(type_filter)
    |> maybe_filter_status(status_filter)
    |> Ash.read!(authorize?: false, load: [:uploaded_by])
  rescue
    _ -> []
  end

  defp maybe_filter_type(query, "all"), do: query

  defp maybe_filter_type(query, type) do
    type_atom = String.to_existing_atom(type)
    Ash.Query.filter(query, import_type == ^type_atom)
  end

  defp maybe_filter_status(query, "all"), do: query

  defp maybe_filter_status(query, status) do
    status_atom = String.to_existing_atom(status)
    Ash.Query.filter(query, status == ^status_atom)
  end

  defp import_type_label(:mde), do: "MDE"
  defp import_type_label(:entity_master), do: "Entity Master"
  defp import_type_label(:enrollment), do: "Enrollment"
  defp import_type_label(:sat), do: "SAT"
  defp import_type_label(other), do: other |> to_string() |> String.replace("_", " ")

  defp format_bytes(nil), do: "—"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.join()
  end

  defp format_number(n), do: to_string(n)

  defp format_duration(nil), do: ""
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_duration(ms), do: "#{Float.round(ms / 60_000, 1)}m"

  defp format_datetime(nil), do: "—"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%b %d, %Y %H:%M")
  end
end
