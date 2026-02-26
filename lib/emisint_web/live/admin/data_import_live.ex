defmodule EmisintWeb.Admin.DataImportLive do
  use EmisintWeb, :live_view

  require Ash.Query

  on_mount {EmisintWeb.LiveUserAuth, :live_user_required}

  @providers [
    {"NWEA MAP", "nwea_map"},
    {"i-Ready", "i_ready"}
  ]

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    oid = user.organization_id

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Emisint.PubSub, "data_sync:#{oid}")
    end

    schools = Ash.read!(Emisint.Accounts.School, tenant: oid, actor: user)
    academic_years = Emisint.Registry.list_academic_years!(tenant: oid, actor: user)
    recent_logs = load_recent_logs(oid, user)

    socket =
      socket
      |> assign(:page_title, "Data Import")
      |> assign(:schools, schools)
      |> assign(:academic_years, academic_years)
      |> assign(:recent_logs, recent_logs)
      |> assign(:selected_school_id, nil)
      |> assign(:selected_year_id, nil)
      |> assign(:selected_provider, "nwea_map")
      |> assign(:importing, false)
      |> assign(:import_result, nil)
      |> allow_upload(:csv_file,
        accept: ~w(.csv),
        max_entries: 1,
        max_file_size: 10_000_000
      )

    {:ok, socket}
  end

  # PubSub: worker broadcasted a status update — reload recent logs
  def handle_info({:data_sync_updated, _org_id}, socket) do
    user = socket.assigns.current_user
    oid = user.organization_id
    logs = load_recent_logs(oid, user)

    {:noreply,
     socket
     |> assign(:recent_logs, logs)
     |> assign(:importing, false)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_field", %{"field" => field, "value" => value}, socket) do
    key = String.to_existing_atom("selected_#{field}")
    {:noreply, assign(socket, key, value)}
  end

  def handle_event(
        "import",
        %{
          "school_id" => school_id,
          "year_id" => year_id,
          "provider" => provider
        },
        socket
      ) do
    if school_id == "" or year_id == "" do
      {:noreply, put_flash(socket, :error, "Please select a school and academic year.")}
    else
      user = socket.assigns.current_user
      oid = user.organization_id

      case consume_uploaded_entries(socket, :csv_file, fn %{path: path}, entry ->
             content = File.read!(path)
             rows = parse_csv(content)
             {:ok, %{rows: rows, filename: entry.client_name, row_count: length(rows)}}
           end) do
        [] ->
          {:noreply, put_flash(socket, :error, "Please select a CSV file to upload.")}

        [%{rows: rows, filename: filename, row_count: row_count}] ->
          %{
            "organization_id" => oid,
            "school_id" => school_id,
            "academic_year_id" => year_id,
            "provider_code" => provider,
            "rows" => rows
          }
          |> Emisint.Workers.CsvImportWorker.new()
          |> Oban.insert!()

          {:noreply,
           socket
           |> assign(:importing, true)
           |> assign(:import_result, %{filename: filename, row_count: row_count})
           |> put_flash(:info, "Import queued: #{filename} (#{row_count} rows). Processing in background…")}
      end
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :csv_file, ref)}
  end

  def render(assigns) do
    assigns = assign(assigns, :providers, @providers)

    ~H"""
    <div class="space-y-8">
      <div>
        <h1 class="text-2xl font-bold">Data Import</h1>
        <p class="text-base-content/60 text-sm mt-1">
          Upload CSV exports from NWEA MAP or i-Ready to populate assessment data.
        </p>
      </div>

      <%!-- Upload form --%>
      <div class="card bg-base-100 shadow-sm border border-base-200">
        <div class="card-body">
          <h2 class="card-title text-lg">Upload Assessment CSV</h2>

          <form phx-submit="import" phx-change="validate" class="space-y-4">
            <%!-- School selector --%>
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">School <span class="text-error">*</span></span>
              </label>
              <select
                name="school_id"
                class="select select-bordered w-full max-w-sm"
                phx-change="update_field"
                phx-value-field="school_id"
              >
                <option value="">Select a school…</option>
                <option :for={school <- @schools} value={school.id} selected={school.id == @selected_school_id}>
                  {school.name}
                </option>
              </select>
            </div>

            <%!-- Academic year selector --%>
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Academic Year <span class="text-error">*</span></span>
              </label>
              <select
                name="year_id"
                class="select select-bordered w-full max-w-sm"
                phx-change="update_field"
                phx-value-field="year_id"
              >
                <option value="">Select a year…</option>
                <option :for={year <- @academic_years} value={year.id} selected={year.id == @selected_year_id}>
                  {year.label}
                </option>
              </select>
            </div>

            <%!-- Provider selector --%>
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Assessment Provider</span>
              </label>
              <div class="flex flex-wrap gap-2">
                <label
                  :for={{label, value} <- @providers}
                  class={[
                    "flex items-center gap-2 px-4 py-2 rounded-lg border-2 cursor-pointer transition-colors",
                    @selected_provider == value && "border-primary bg-primary/10",
                    @selected_provider != value && "border-base-300 hover:border-primary/50"
                  ]}
                >
                  <input
                    type="radio"
                    name="provider"
                    value={value}
                    checked={@selected_provider == value}
                    class="radio radio-sm radio-primary"
                    phx-change="update_field"
                    phx-value-field="provider"
                  />
                  {label}
                </label>
              </div>
            </div>

            <%!-- File upload area --%>
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">CSV File <span class="text-error">*</span></span>
              </label>
              <div
                class="border-2 border-dashed border-base-300 rounded-lg p-6 text-center hover:border-primary/50 transition-colors"
                phx-drop-target={@uploads.csv_file.ref}
              >
                <.icon name="hero-document-text" class="size-8 text-base-content/40 mx-auto" />
                <p class="mt-2 text-base-content/60 text-sm">
                  Drag and drop your CSV file here, or
                </p>
                <label class="mt-2 btn btn-sm btn-outline cursor-pointer">
                  Browse File
                  <.live_file_input upload={@uploads.csv_file} class="hidden" />
                </label>
                <p class="text-xs text-base-content/40 mt-2">CSV files up to 10MB</p>
              </div>

              <%!-- Upload entry previews --%>
              <div :for={entry <- @uploads.csv_file.entries} class="mt-2 flex items-center gap-2 p-2 bg-base-200 rounded-lg">
                <.icon name="hero-document-text" class="size-5 text-primary shrink-0" />
                <div class="flex-1 min-w-0">
                  <div class="text-sm font-medium truncate">{entry.client_name}</div>
                  <div class="text-xs text-base-content/60">{format_bytes(entry.client_size)}</div>
                </div>
                <div class="flex items-center gap-2">
                  <progress class="progress progress-primary w-16" value={entry.progress} max="100"></progress>
                  <button
                    type="button"
                    phx-click="cancel-upload"
                    phx-value-ref={entry.ref}
                    class="btn btn-ghost btn-xs btn-circle"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
              </div>

              <%!-- Upload errors --%>
              <div :for={err <- upload_errors(@uploads.csv_file)} class="mt-1 text-sm text-error flex items-center gap-1">
                <.icon name="hero-exclamation-circle" class="size-4" />
                {upload_error_msg(err)}
              </div>
            </div>

            <div class="card-actions">
              <button
                type="submit"
                class={["btn btn-primary gap-2", @importing && "loading"]}
                disabled={@importing}
              >
                <.icon :if={!@importing} name="hero-arrow-up-tray" class="size-4" />
                {if @importing, do: "Processing…", else: "Start Import"}
              </button>
            </div>
          </form>
        </div>
      </div>

      <%!-- Import history --%>
      <div class="space-y-3">
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-semibold">Recent Imports</h2>
          <div :if={@importing} class="flex items-center gap-2 text-sm text-base-content/60">
            <span class="loading loading-spinner loading-xs"></span>
            Processing import…
          </div>
        </div>

        <div :if={@recent_logs == []} class="card bg-base-200">
          <div class="card-body items-center py-8 text-center">
            <p class="text-base-content/60">No imports yet. Upload a CSV file to get started.</p>
          </div>
        </div>

        <div :if={@recent_logs != []} class="overflow-x-auto">
          <table class="table table-sm bg-base-100 rounded-lg shadow-sm">
            <thead>
              <tr>
                <th>Status</th>
                <th>Type</th>
                <th>Started</th>
                <th class="text-right">Processed</th>
                <th class="text-right">Failed</th>
                <th>Details</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={log <- @recent_logs}>
                <td><.sync_status_badge status={log.status} /></td>
                <td class="capitalize">{log.job_type |> to_string() |> String.replace("_", " ")}</td>
                <td class="text-base-content/60 text-xs whitespace-nowrap">
                  {format_datetime(log.inserted_at)}
                </td>
                <td class="text-right">{log.records_processed || "—"}</td>
                <td class="text-right">{log.records_failed || "—"}</td>
                <td class="text-xs text-base-content/60 max-w-xs truncate">
                  {log.error_message || (log.metadata["provider_code"] && "Provider: #{log.metadata["provider_code"]}")}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  def sync_status_badge(assigns) do
    ~H"""
    <span :if={@status == :pending} class="badge badge-ghost badge-sm">Pending</span>
    <span :if={@status == :running} class="badge badge-info badge-sm gap-1">
      <span class="loading loading-spinner loading-xs"></span> Running
    </span>
    <span :if={@status == :completed} class="badge badge-success badge-sm">Completed</span>
    <span :if={@status == :failed} class="badge badge-error badge-sm">Failed</span>
    """
  end

  # --- Helpers ---

  defp load_recent_logs(oid, user) do
    Emisint.Analytics.DataSyncLog
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(20)
    |> Ash.read!(tenant: oid, actor: user)
  end

  defp parse_csv(content) do
    lines = String.split(content, ~r/\r?\n/, trim: true)

    case lines do
      [] ->
        []

      [_header] ->
        []

      [header_line | data_lines] ->
        headers =
          header_line
          |> String.split(",")
          |> Enum.map(&String.trim/1)

        Enum.map(data_lines, fn line ->
          values = String.split(line, ",") |> Enum.map(&String.trim/1)
          headers |> Enum.zip(values) |> Map.new()
        end)
    end
  end

  defp format_bytes(nil), do: ""

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_datetime(nil), do: "—"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%b %d, %Y %H:%M")
  end

  defp upload_error_msg(:too_large), do: "File is too large (max 10MB)"
  defp upload_error_msg(:not_accepted), do: "Only CSV files are accepted"
  defp upload_error_msg(:too_many_files), do: "Only one file allowed"
  defp upload_error_msg(err), do: inspect(err)
end
