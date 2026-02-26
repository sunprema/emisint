defmodule EmisintWeb.Admin.DataImportLive do
  use EmisintWeb, :live_view

  require Ash.Query

  @providers [
    {"NWEA MAP", "nwea_map"},
    {"i-Ready", "i_ready"}
  ]

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    oid = user.organization_id
    scope = socket.assigns.scope

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Emisint.PubSub, "data_sync:#{oid}")
    end

    schools = Ash.read!(Emisint.Accounts.School, scope: scope)
    academic_years = Emisint.Registry.list_academic_years!(scope: scope)
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
      |> assign(:providers, @providers)
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

  def handle_event("update_field", %{"_target" => [field]} = params, socket) do
    key = String.to_existing_atom("selected_#{field}")
    {:noreply, assign(socket, key, params[field])}
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
           |> put_flash(
             :info,
             "Import queued: #{filename} (#{row_count} rows). Processing in background…"
           )}
      end
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :csv_file, ref)}
  end

  def render(assigns) do
    assigns = assign(assigns, :providers, @providers)

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-6xl mx-auto space-y-8">
        <%!-- Page header --%>
        <div class="flex items-center gap-4">
          <div class="p-2.5 rounded-2xl bg-primary/10 border border-primary/20">
            <.icon name="hero-arrow-up-tray" class="size-6 text-primary" />
          </div>
          <div>
            <h1 class="text-2xl font-bold tracking-tight">Data Import</h1>
            <p class="text-sm text-base-content/50 mt-0.5">
              Upload CSV exports from NWEA MAP or i-Ready to populate assessment data.
            </p>
          </div>
        </div>

        <%!-- Two-column layout --%>
        <div class="grid grid-cols-1 lg:grid-cols-5 gap-6 items-start">
          <%!-- Upload form — 3 cols --%>
          <div class="lg:col-span-3 rounded-2xl bg-base-100 border border-base-200 shadow-sm overflow-hidden">
            <div class="px-6 py-4 border-b border-base-200">
              <h2 class="font-semibold">Upload Assessment CSV</h2>
              <p class="text-xs text-base-content/40 mt-0.5">
                All fields are required before submitting
              </p>
            </div>

            <form phx-submit="import" phx-change="validate" class="p-6 space-y-6">
              <%!-- School + Year row --%>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div class="space-y-1.5">
                  <label class="text-sm font-medium">
                    School <span class="text-error text-xs">*</span>
                  </label>
                  <select
                    name="school_id"
                    class="w-full rounded-xl border border-base-300 bg-base-100 px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-primary/25 focus:border-primary transition-all"
                    phx-change="update_field"
                    phx-value-field="school_id"
                  >
                    <option value="">Select a school…</option>
                    <option
                      :for={school <- @schools}
                      value={school.id}
                      selected={school.id == @selected_school_id}
                    >
                      {school.name}
                    </option>
                  </select>
                </div>

                <div class="space-y-1.5">
                  <label class="text-sm font-medium">
                    Academic Year <span class="text-error text-xs">*</span>
                  </label>
                  <select
                    name="year_id"
                    class="w-full rounded-xl border border-base-300 bg-base-100 px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-primary/25 focus:border-primary transition-all"
                    phx-change="update_field"
                    phx-value-field="year_id"
                  >
                    <option value="">Select a year…</option>
                    <option
                      :for={year <- @academic_years}
                      value={year.id}
                      selected={year.id == @selected_year_id}
                    >
                      {year.label}
                    </option>
                  </select>
                </div>
              </div>

              <%!-- Provider selector --%>
              <div class="space-y-1.5">
                <label class="text-sm font-medium">Assessment Provider</label>
                <div class="flex gap-3">
                  <label
                    :for={{label, value} <- @providers}
                    class={[
                      "flex-1 flex items-center gap-3 px-4 py-3 rounded-xl border-2 cursor-pointer transition-all select-none",
                      @selected_provider == value &&
                        "border-primary bg-primary/5",
                      @selected_provider != value &&
                        "border-base-200 hover:border-base-300 bg-base-50/50"
                    ]}
                  >
                    <div class={[
                      "size-4 rounded-full border-2 flex items-center justify-center shrink-0 transition-all",
                      @selected_provider == value && "border-primary",
                      @selected_provider != value && "border-base-300"
                    ]}>
                      <div
                        :if={@selected_provider == value}
                        class="size-1.5 rounded-full bg-primary"
                      >
                      </div>
                    </div>
                    <input
                      type="radio"
                      name="provider"
                      value={value}
                      checked={@selected_provider == value}
                      class="hidden"
                      phx-change="update_field"
                      phx-value-field="provider"
                    />
                    <span class="text-sm font-medium">{label}</span>
                  </label>
                </div>
              </div>

              <%!-- File upload drop zone --%>
              <div class="space-y-2">
                <label class="text-sm font-medium">
                  CSV File <span class="text-error text-xs">*</span>
                </label>

                <div
                  class="relative rounded-xl border-2 border-dashed border-base-300 hover:border-primary/40 bg-base-50/50 transition-colors group cursor-pointer"
                  phx-drop-target={@uploads.csv_file.ref}
                >
                  <label class="flex flex-col items-center justify-center py-10 px-6 text-center cursor-pointer">
                    <div class="p-3 rounded-2xl bg-base-200 group-hover:bg-primary/10 transition-colors mb-3">
                      <.icon
                        name="hero-document-text"
                        class="size-7 text-base-content/30 group-hover:text-primary transition-colors"
                      />
                    </div>
                    <p class="text-sm text-base-content/50">
                      Drag & drop your CSV here, or{" "}
                      <span class="text-primary font-medium hover:underline">browse</span>
                    </p>
                    <p class="text-xs text-base-content/30 mt-1">CSV files up to 10 MB</p>
                    <.live_file_input upload={@uploads.csv_file} class="hidden" />
                  </label>
                </div>

                <%!-- File entry preview --%>
                <div
                  :for={entry <- @uploads.csv_file.entries}
                  class="flex items-center gap-3 p-3 rounded-xl border border-base-200 bg-base-50"
                >
                  <div class="p-2 rounded-lg bg-primary/10 shrink-0">
                    <.icon name="hero-document-text" class="size-4 text-primary" />
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="text-sm font-medium truncate">{entry.client_name}</div>
                    <div class="w-full bg-base-200 rounded-full h-1 mt-1.5">
                      <div
                        class="bg-primary h-1 rounded-full transition-all duration-300"
                        style={"width: #{entry.progress}%"}
                      >
                      </div>
                    </div>
                  </div>
                  <span class="text-xs text-base-content/40 shrink-0">
                    {format_bytes(entry.client_size)}
                  </span>
                  <button
                    type="button"
                    phx-click="cancel-upload"
                    phx-value-ref={entry.ref}
                    class="p-1.5 rounded-lg hover:bg-error/10 text-base-content/30 hover:text-error transition-colors"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>

                <%!-- Upload errors --%>
                <div
                  :for={err <- upload_errors(@uploads.csv_file)}
                  class="flex items-center gap-2 text-sm text-error bg-error/5 border border-error/10 rounded-xl px-3 py-2.5"
                >
                  <.icon name="hero-exclamation-circle" class="size-4 shrink-0" />
                  {upload_error_msg(err)}
                </div>
              </div>

              <%!-- Submit button --%>
              <button
                type="submit"
                class={[
                  "w-full flex items-center justify-center gap-2 py-3 rounded-xl font-medium text-sm transition-all",
                  !@importing &&
                    "bg-primary text-primary-content hover:opacity-90 active:scale-[0.99] shadow-sm shadow-primary/20",
                  @importing && "bg-primary/50 text-primary-content/70 cursor-not-allowed"
                ]}
                disabled={@importing}
              >
                <span :if={@importing} class="loading loading-spinner loading-sm"></span>
                <.icon :if={!@importing} name="hero-arrow-up-tray" class="size-4" />
                {if @importing, do: "Processing…", else: "Start Import"}
              </button>
            </form>
          </div>

          <%!-- Recent imports — 2 cols --%>
          <div class="lg:col-span-2 rounded-2xl bg-base-100 border border-base-200 shadow-sm overflow-hidden">
            <div class="px-6 py-4 border-b border-base-200 flex items-center justify-between">
              <div>
                <h2 class="font-semibold">Recent Imports</h2>
                <p class="text-xs text-base-content/40 mt-0.5">Last 20 jobs</p>
              </div>
              <div :if={@importing} class="flex items-center gap-1.5 text-xs text-base-content/40">
                <span class="loading loading-spinner loading-xs"></span> Processing…
              </div>
            </div>

            <%!-- Empty state --%>
            <div
              :if={@recent_logs == []}
              class="flex flex-col items-center justify-center py-16 px-6 text-center"
            >
              <div class="p-3 rounded-2xl bg-base-200 mb-3">
                <.icon name="hero-inbox" class="size-6 text-base-content/25" />
              </div>
              <p class="text-sm font-medium text-base-content/40">No imports yet</p>
              <p class="text-xs text-base-content/30 mt-1">Upload a CSV file to get started.</p>
            </div>

            <%!-- Log entries --%>
            <div :if={@recent_logs != []} class="divide-y divide-base-200">
              <div
                :for={log <- @recent_logs}
                class="px-5 py-3.5 hover:bg-base-50 transition-colors"
              >
                <div class="flex items-start justify-between gap-2">
                  <div class="flex items-center gap-2 min-w-0">
                    <.sync_status_dot status={log.status} />
                    <span class="text-sm font-medium capitalize truncate">
                      {log.job_type |> to_string() |> String.replace("_", " ")}
                    </span>
                  </div>
                  <span class="text-xs text-base-content/35 shrink-0 mt-0.5">
                    {format_datetime(log.inserted_at)}
                  </span>
                </div>

                <div class="flex flex-wrap items-center gap-x-3 gap-y-0.5 mt-1 ml-4 text-xs text-base-content/45">
                  <span :if={log.records_processed}>
                    <span class="text-success">✓</span> {log.records_processed} rows
                  </span>
                  <span :if={log.records_failed && log.records_failed > 0} class="text-error">
                    <span>✗</span> {log.records_failed} failed
                  </span>
                  <span :if={log.metadata["provider_code"]} class="uppercase tracking-wide font-medium">
                    {log.metadata["provider_code"] |> to_string() |> String.replace("_", " ")}
                  </span>
                </div>

                <p :if={log.error_message} class="ml-4 mt-1 text-xs text-error/70 truncate">
                  {log.error_message}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def sync_status_dot(assigns) do
    ~H"""
    <span
      :if={@status == :pending}
      class="inline-block size-2 rounded-full bg-base-300 shrink-0 mt-0.5"
    >
    </span>
    <span
      :if={@status == :running}
      class="inline-block size-2 rounded-full bg-info animate-pulse shrink-0 mt-0.5"
    >
    </span>
    <span
      :if={@status == :completed}
      class="inline-block size-2 rounded-full bg-success shrink-0 mt-0.5"
    >
    </span>
    <span
      :if={@status == :failed}
      class="inline-block size-2 rounded-full bg-error shrink-0 mt-0.5"
    >
    </span>
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
    |> Ash.Query.sort(updated_at: :desc)
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
